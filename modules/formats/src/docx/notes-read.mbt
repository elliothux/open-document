///|
priv struct DocNote {
  key : String
  node : Int
  paragraphs : Array[Int]
  texts : Array[Int]
  text : String
  reason : String
}

///|
priv struct NotesSource {
  part : String
  document : @xml.Document
  tree : WordTree
  entries : Array[DocNote]
}

///|
fn note_key(value : String) -> String raise @failure.Failure {
  let value = @string.parse_int(value.trim()) catch {
    _ => @failure.reject("protected-content", "Invalid note identity")
  }
  guard value >= 0 else {
    @failure.reject("protected-content", "Invalid note identity")
  }
  value.to_string()
}

///|
fn read_doc_note(
  tree : WordTree,
  id : Int,
  kind : String,
) -> DocNote raise @failure.Failure {
  let node = tree.nodes[id]
  let key = note_key(node.attribute("id", uri=word_uri).unwrap_or(""))
  let paragraphs = tree.children[id].filter(child => {
    tree.nodes[child].uri == word_uri && tree.nodes[child].name == "p"
  })
  let texts : Array[Int] = []
  let content : Array[String] = []
  let mut reason = ""
  if !node.attributes.all(a => {
      a.uri == word_uri && ["id", "type"].contains(a.name)
    }) ||
    !["", "normal"].contains(node.attribute("type", uri=word_uri).unwrap_or("")) ||
    paragraphs.is_empty() ||
    tree.children[id].length() != paragraphs.length() {
    reason = "protected-content:note-content-requires-structured-editing"
  }
  let mut markers = 0
  for paragraph in paragraphs {
    let parts : Array[String] = []
    for child in tree.children[paragraph] {
      let run = tree.nodes[child]
      if run.uri == word_uri && run.name == "pPr" {
        if tree.descendants(child).any(id => tree.nodes[id].name == "pPrChange") {
          reason = "protected-content:tracked-note-properties"
        }
        continue
      }
      if run.uri != word_uri || run.name != "r" {
        reason = "protected-content:note-content-requires-structured-editing"
      }
      for element in tree.descendants(child) {
        let item = tree.nodes[element]
        if item.uri == word_uri && item.name == "t" {
          parts.push(item.text)
          texts.push(element)
          if !item.attributes.all(a => {
              a.uri == "http://www.w3.org/XML/1998/namespace" &&
              a.name == "space"
            }) ||
            tree.source[item.start:item.end].contains("<!--") ||
            tree.source[item.start:item.end].contains("<?") {
            reason = "protected-content:opaque-note-text"
          }
        } else if item.uri == word_uri &&
          ["br", "cr", "tab"].contains(item.name) {
          parts.push(if item.name == "tab" { "\t" } else { "\n" })
        }
      }
      for element in tree.children[child] {
        let item = tree.nodes[element]
        if item.uri == word_uri && item.name == "rPr" {
          if tree
            .descendants(element)
            .any(n => tree.nodes[n].name == "rPrChange") {
            reason = "protected-content:tracked-note-properties"
          }
        } else if item.uri == word_uri &&
          item.name == kind + "Ref" &&
          item.attributes.is_empty() &&
          tree.children[element].is_empty() {
          markers += 1
          if paragraph != paragraphs[0] {
            reason = "protected-content:note-reference-marker"
          }
        } else if item.uri != word_uri ||
          item.name != "t" ||
          !tree.children[element].is_empty() {
          reason = "protected-content:note-content-requires-structured-editing"
        }
      }
    }
    content.push(parts.join(""))
  }
  if markers != 1 {
    reason = "protected-content:note-reference-marker"
  }
  let text = content.join("\n")
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Note text exceeds32767 units")
  }
  { key, node: id, paragraphs, texts, text, reason, }
}

///|
fn Session::note_source(
  self : Session,
  kind : String,
) -> NotesSource? raise @failure.Failure {
  guard ["footnote", "endnote"].contains(kind) else {
    @failure.reject("invalid-operation", "Invalid note kind")
  }
  let links = self.relationships()
  let uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/" +
    kind +
    "s"
  let candidates = links.filter(link => {
    link.owner == self.main && link.kind == uri
  })
  guard candidates.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate note part relationships")
  }
  guard candidates.get(0) is Some(link) else { return None }
  guard !link.external &&
    links
    .filter(other => !other.external && other.target == link.target)
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Shared or external note parts are protected",
    )
  }
  let document = self.part_xml(link.target)
  let tree = WordTree::new(document)
  guard tree.nodes[0].uri == word_uri && tree.nodes[0].name == kind + "s" else {
    @failure.reject("protected-content", "Invalid note part root")
  }
  let keys : Set[String] = Set([])
  let entries : Array[DocNote] = []
  let mut units = 0
  for id in tree.children[0] {
    let node = tree.nodes[id]
    guard node.uri == word_uri && node.name == kind else {
      @failure.reject("protected-content", "Unsupported note part content")
    }
    let role = node.attribute("type", uri=word_uri).unwrap_or("")
    let native_id = @string.parse_int(
      node.attribute("id", uri=word_uri).unwrap_or("").trim(),
    ) catch {
      _ => @failure.reject("protected-content", "Invalid note identity")
    }
    guard !keys.contains(native_id.to_string()) else {
      @failure.reject("protected-content", "Duplicate note identity")
    }
    keys.add(native_id.to_string())
    if ["separator", "continuationSeparator", "continuationNotice"].contains(
        role,
      ) {
      continue
    }
    let entry = read_doc_note(tree, id, kind)
    units += entry.text.length()
    guard entries.length() < 4096 && units <= 1048576 else {
      @failure.reject("limit-exceeded", "Note catalog exceeds limits")
    }
    entries.push(entry)
  }
  Some({ part: link.target, document, tree, entries, })
}

///|
/// Reads native note bodies without changing their reference or source XML.
pub fn Session::notes(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let entries : Array[Json] = []
  let tree = WordTree::new(self.document())
  for kind in ["footnote", "endnote"] {
    let references : Map[String, Int] = Map([])
    for id in tree.order {
      let node = tree.nodes[id]
      if node.uri == word_uri && node.name == kind + "Reference" {
        let key = note_key(node.attribute("id", uri=word_uri).unwrap_or(""))
        references[key] = references.get(key).unwrap_or(0) + 1
      }
    }
    guard references.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Note references exceed limits")
    }
    let known : Set[String] = Set([])
    let source = self.note_source(kind)
    if source is Some(source) {
      for note in source.entries {
        known.add(note.key)
        entries.push({
          "kind": kind,
          "id": note.key,
          "text": note.text,
          "reason": note.reason,
          "references": references.get(note.key).unwrap_or(0),
        })
      }
    }
    for key, count in references {
      if !known.contains(key) {
        entries.push({
          "kind": kind,
          "id": key,
          "text": "",
          "reason": "protected-content:missing-note-body",
          "references": count,
        })
      }
    }
  }
  guard entries.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Combined note catalog exceeds limits")
  }
  { "revision": self.revision, "entries": entries }
}
