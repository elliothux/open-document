///|
let word_uri = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
priv struct TextNode {
  id : Int
  paragraph : Int
  run : Int
}

///|
pub struct Session {
  priv opc : @opc.Package
  priv main : String
  priv mut document : @xml.Document?
  priv mut texts : Array[TextNode]
  priv mut selection : Selection?
  priv mut typing_text : Int?
  priv mut typing_format : CharacterFormat?
  priv mut input_group : Int?
  priv mut vertical_x : Double?
  priv mut navigation_layout : Int
  priv history : Array[Edit]
  priv redo : Array[Edit]
  priv mut history_bytes : Int
  priv mut revision : Int
  priv mut composition : Composition?
  priv mut composition_id : Int
  priv mut closed : Bool
  priv diagnostics : Array[String]
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  Session::from_package(@opc.Package::open(bytes, budget))
}

///|
fn Session::from_package(opc : @opc.Package) -> Session raise @failure.Failure {
  errdefer opc.close()
  let mut main : String? = None
  for rel in opc.relationships() {
    if rel.owner.is_empty() &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" {
      guard !rel.external && main is None else {
        @failure.reject(
          "malformed-docx", "Invalid or duplicate main relationship",
        )
      }
      main = Some(rel.target)
    }
    guard !rel.kind.has_prefix(
      "http://purl.oclc.org/ooxml/officeDocument/relationships/",
    ) else {
      @failure.reject("unsupported-docx", "Strict OOXML is unsupported")
    }
    guard !rel.kind.has_prefix(
      "http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/",
    ) else {
      @failure.reject("unsupported-docx", "Signed packages are unsupported")
    }
  }
  guard main is Some(main) else {
    @failure.reject("malformed-docx", "Missing officeDocument relationship")
  }
  guard opc.content_type(main) ==
    Some(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
    ) else {
    @failure.reject(
      "unsupported-docx",
      "Only Transitional DOCX documents are supported",
      part=main,
    )
  }
  let document = opc.xml(main)
  let nodes = document.nodes()
  guard nodes[0].uri == word_uri && nodes[0].name == "document" else {
    @failure.reject(
      "unsupported-docx",
      "Unsupported Word document namespace",
      part=main,
    )
  }
  let diagnostics : Array[String] = []
  let mut body = -1
  for node in nodes {
    if node.parent == 0 && node.uri == word_uri && node.name == "body" {
      guard body < 0 else {
        @failure.reject("malformed-docx", "Duplicate document body", part=main)
      }
      body = node.id
    }
  }
  guard body >= 0 else {
    @failure.reject("malformed-docx", "Missing document body", part=main)
  }
  for node in nodes {
    if node.parent == body &&
      !(node.uri == word_uri && (node.name == "p" || node.name == "sectPr")) {
      diagnostics.push("preserved-structure:" + node.qualified)
    }
  }
  {
    opc,
    main,
    document: Some(document),
    texts: docx_texts(WordTree::new(document)),
    selection: None,
    typing_text: None,
    typing_format: None,
    input_group: None,
    vertical_x: None,
    navigation_layout: -1,
    history: [],
    redo: [],
    history_bytes: 0,
    revision: 0,
    composition: None,
    composition_id: 0,
    closed: false,
    diagnostics,
  }
}

///|
fn Session::document(self : Session) -> @xml.Document raise @failure.Failure {
  guard !self.closed && self.document is Some(document) else {
    @failure.reject("closed-session", "DOCX session is closed")
  }
  document
}

///|
pub fn Session::query(self : Session) -> Json raise @failure.Failure {
  let document = self.display_document()
  let tree = WordTree::new(document)
  let nodes = tree.nodes
  let texts : Array[Json] = []
  for
    node in (if self.composition is Some(_) {
      docx_texts(tree)
    } else {
      self.texts
    }) {
    texts.push({
      "id": node.id,
      "paragraph": node.paragraph,
      "run": node.run,
      "text": nodes[node.id].text,
    })
  }
  let rels : Array[Json] = []
  for rel in self.opc.relationships() {
    rels.push({
      "owner": rel.owner,
      "id": rel.id,
      "type": rel.kind,
      "target": rel.target,
      "external": rel.external,
    })
  }
  {
    "revision": self.revision,
    "compositionId": self.composition
    .map(composition => Json(composition.id))
    .unwrap_or(Json::null()),
    "mainPart": self.main,
    "texts": texts,
    "relationships": rels,
    "diagnostics": self.diagnostics,
    "decodedBytes": self.opc.decoded_bytes(),
  }
}

///|
pub fn Session::replace(
  self : Session,
  id : Int,
  revision : Int,
  text : String,
) -> Int raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  guard self.texts.iter().filter(node => node.id == id).next() is Some(node) else {
    @failure.reject("invalid-operation", "Unknown or unsupported text node")
  }
  let nodes = WordTree::new(document).nodes
  let texts = self.texts.filter(item => item.paragraph == node.paragraph)
  let before = nodes[id].text
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Command input exceeds UTF-16 budget")
  }
  if before == text {
    self.input_group = None
    return self.revision
  }
  let mut offset = 0
  for item in texts {
    if item.id == id {
      break
    }
    offset += nodes[item.id].text.length()
  }
  let after = self.selection.map(selection => {
    if selection.anchor.paragraph != node.paragraph &&
      selection.focus.paragraph != node.paragraph {
      return {
        anchor: { ..selection.anchor, frameStart: None, },
        focus: { ..selection.focus, frameStart: None, },
      }
    }
    let content = texts.map(item => nodes[item.id].text).join("")
    let updated = content[:offset].to_owned() +
      text +
      content[offset + before.length():].to_owned()
    let boundaries = @layout.grapheme_boundaries(updated)
    fn mapped(position : Position) -> Position {
      if position.paragraph != node.paragraph {
        return { ..position, frameStart: None, }
      }
      let mapped = if position.offset < offset {
        position.offset
      } else if position.offset <= offset + before.length() {
        offset + text.length()
      } else {
        position.offset - before.length() + text.length()
      }
      {
        ..position,
        bidiLevel: None,
        frameStart: None,
        offset: boundaries
        .iter()
        .find_first(boundary => boundary >= mapped)
        .unwrap(),
      }
    }
    { anchor: mapped(selection.anchor), focus: mapped(selection.focus), }
  })
  self.commit_text(Map::from_array([(id, text)]), after, node.paragraph)
  self.revision
}

///|
pub fn Session::save(self : Session) -> Bytes raise @failure.Failure {
  self.check_idle()
  let document = self.document()
  let replacements : Map[String, Bytes] = Map([])
  if !document.is_original() {
    replacements[self.main] = document.bytes()
  }
  self.opc.save(replacements)
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.composition = None
  self.opc.close()
  self.document = None
  self.texts.clear()
  self.selection = None
  self.typing_text = None
  self.typing_format = None
  self.input_group = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.history.clear()
  self.redo.clear()
  self.history_bytes = 0
  self.diagnostics.clear()
}
