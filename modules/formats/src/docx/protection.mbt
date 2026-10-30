///|
fn WordTree::protection_nodes(self : WordTree) -> Array[Int32] {
  self.children[0].filter(id => {
    self.nodes[id].uri == word_uri &&
    self.nodes[id].name == "documentProtection"
  })
}

///|
fn WordTree::protection_enabled(self : WordTree, id : Int32) -> Bool {
  !["0", "false", "off"].contains(
    self.nodes[id].attribute("enforcement", uri=word_uri).unwrap_or("0"),
  )
}

///|
fn WordTree::protection_credentials(
  self : WordTree,
  id : Int32,
) -> (Bytes, Bytes, Int32)? raise @failure.Failure {
  let node = self.nodes[id]
  let names = ["algorithmName", "hashValue", "saltValue", "spinCount"]
  if !names.any(name => node.attribute(name, uri=word_uri) is Some(_)) {
    return None
  }
  guard node.attribute("algorithmName", uri=word_uri) == Some("SHA-512") &&
    names.all(name => node.attribute(name, uri=word_uri) is Some(_)) else {
    @failure.reject(
      "protected-content", "Unsupported document protection password algorithm",
    )
  }
  let value = node.attribute("hashValue", uri=word_uri).unwrap()
  let salt = node.attribute("saltValue", uri=word_uri).unwrap()
  let count = node.attribute("spinCount", uri=word_uri).unwrap()
  guard value.length() <= 128 &&
    salt.length() <= 128 &&
    !count.is_empty() &&
    count.length() <= 7 &&
    count.iter().all(c => c >= '0' && c <= '9') else {
    @failure.reject(
      "protected-content", "Invalid document protection credentials",
    )
  }
  let count = @string.parse_int(count) catch {
    _ =>
      @failure.reject(
        "protected-content", "Invalid document protection spin count",
      )
  }
  let salt = @base64.decode(salt[:]) catch {
    _ =>
      @failure.reject("protected-content", "Invalid document protection salt")
  }
  let hash = @base64.decode(value[:]) catch {
    _ =>
      @failure.reject("protected-content", "Invalid document protection hash")
  }
  guard count <= 1000000 &&
    salt.length() >= 1 &&
    salt.length() <= 64 &&
    hash.length() == 64 else {
    @failure.reject(
      "protected-content", "Invalid document protection credentials",
    )
  }
  Some((salt, hash, count))
}

///|
fn WordTree::check_protection_node(
  self : WordTree,
  id : Int32,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  let source = self.source[node.start:node.end]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") &&
    node.attributes.all(a => {
      a.uri == word_uri &&
      [
        "edit", "enforcement", "formatting", "algorithmName", "hashValue", "saltValue",
        "spinCount",
      ].contains(a.name)
    }) &&
    [None, Some("readOnly"), Some("forms")].contains(
      node.attribute("edit", uri=word_uri),
    ) &&
    ["0", "1", "false", "true", "off", "on"].contains(
      node.attribute("enforcement", uri=word_uri).unwrap_or("0"),
    ) &&
    [None, Some("0"), Some("false"), Some("off")].contains(
      node.attribute("formatting", uri=word_uri),
    ) &&
    (
      !self.protection_enabled(id) ||
      [Some("readOnly"), Some("forms")].contains(
        node.attribute("edit", uri=word_uri),
      )
    ) else {
    @failure.reject(
      "protected-content", "Unsupported document protection metadata or restriction",
    )
  }
  ignore(self.protection_credentials(id))
}

///|
fn Session::check_document_protection(
  self : Session,
) -> Unit raise @failure.Failure {
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let nodes = tree.protection_nodes()
    guard nodes.length() <= 1 && !nodes.any(id => tree.protection_enabled(id)) else {
      @failure.reject("protected-content", "Document editing is protected")
    }
  }
}

///|
/// Reads editing restrictions without changing the document or exposing credentials.
pub fn Session::document_protection(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let mut enabled = false
  let mut password = false
  let mut reason = ""
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let nodes = tree.protection_nodes()
    enabled = nodes.any(id => tree.protection_enabled(id))
    password = enabled &&
      nodes.any(id => {
        tree.nodes[id].attributes.any(a => {
          ["algorithmName", "cryptAlgorithmSid", "hash", "hashValue"].contains(
            a.name,
          )
        })
      })
    try {
      guard nodes.length() <= 1 else {
        @failure.reject(
          "protected-content", "Duplicate document protection settings",
        )
      }
      for id in nodes {
        tree.check_protection_node(id)
      }
    } catch {
      @failure.Failure(message~, ..) => reason = message
    }
  }
  {
    "revision": revision,
    "protected": enabled,
    "passwordRequired": password,
    "reason": reason,
  }
}

///|
/// Enables read-only editing protection or removes a known restriction after password verification.
pub fn Session::set_document_protection(
  self : Session,
  revision : Int32,
  enabled : Bool,
  password : String,
  salt : Bytes,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  @protection.password(password)
  guard salt.length() == (if enabled && !password.is_empty() { 16 } else { 0 }) else {
    @failure.reject(
      "invalid-operation", "New document protection passwords require a 16-byte random salt",
    )
  }
  let original = self.settings_part()
  if original is None && !enabled {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = original.unwrap_or_else(() => {
    self.new_word_part("settings", parts, edits, created)
  })
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let tree = WordTree::new(document)
  let nodes = tree.protection_nodes()
  guard nodes.length() <= 1 else {
    @failure.reject(
      "protected-content", "Duplicate document protection settings",
    )
  }
  let target = nodes.get(0)
  if target is Some(id) {
    tree.check_protection_node(id)
  }
  let locked = target.map(id => tree.protection_enabled(id)).unwrap_or(false)
  if enabled && locked {
    @failure.reject(
      "invalid-operation", "Unprotect the document before changing its password",
    )
  }
  if !enabled && !locked {
    return self.edit_state()
  }
  if !enabled &&
    target.bind(id => tree.protection_credentials(id))
    is Some((salt, hash, count)) {
    guard @protection.matches(password, salt, count, hash) else {
      @failure.reject("protected-content", "Document password is incorrect")
    }
  }
  let markup = if enabled {
    let credentials = if password.is_empty() {
      ""
    } else {
      " od:algorithmName=\"SHA-512\" od:hashValue=\"\{@base64.encode(@protection.hash(password,salt,100000)[:])}\" od:saltValue=\"\{@base64.encode(salt[:])}\" od:spinCount=\"100000\""
    }
    "<od:documentProtection xmlns:od=\"\{word_uri}\" od:edit=\"readOnly\" od:enforcement=\"1\"\{credentials}/>"
  } else {
    ""
  }
  let change = if target is Some(_) || tree.nodes[0].empty {
    properties_change(tree, document, 0, "documentProtection", markup).unwrap()
  } else {
    let previous = tree.children[0]
      .iter()
      .filter(id => {
        tree.nodes[id].uri == word_uri &&
        [
          "writeProtection", "view", "zoom", "removePersonalInformation", "removeDateAndTime",
          "doNotDisplayPageBoundaries", "displayBackgroundShape", "printPostScriptOverText",
          "printFractionalCharacterWidth", "printFormsData", "embedTrueTypeFonts",
          "embedSystemFonts", "saveSubsetFonts", "saveFormsData", "mirrorMargins",
          "alignBordersAndEdges", "bordersDoNotSurroundHeader", "bordersDoNotSurroundFooter",
          "gutterAtTop", "hideSpellingErrors", "hideGrammaticalErrors", "activeWritingStyle",
          "proofState", "formsDesign", "attachedTemplate", "linkStyles", "stylePaneFormatFilter",
          "stylePaneSortMethod", "documentType", "mailMerge", "revisionView", "trackRevisions",
          "doNotTrackMoves", "doNotTrackFormatting",
        ].contains(tree.nodes[id].name)
      })
      .last()
    {
      node: 0,
      offset: previous
      .map(id => tree.nodes[id].end)
      .unwrap_or(tree.nodes[0].opening_end) -
      tree.nodes[0].start,
      length: 0,
      xml: markup,
    }
  }
  let (candidate, edit) = document.edit_source([change])
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  let bytes = xml_part_edit_bytes(edits, created)
  guard bytes <= history_byte_limit else {
    @failure.reject(
      "limit-exceeded", "Document protection history exceeds budget",
    )
  }
  let body = WordTree::new(self.document())
  let paragraphs = body.order.filter(id => {
    body.nodes[id].uri == word_uri && body.nodes[id].name == "p"
  })
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes,
    },
    self.document(),
    parts~,
    protection_edit=true,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
