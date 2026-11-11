///|
let word_uri = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
priv struct TextNode {
  id : Int32
  paragraph : Int32
  run : Int32
}

///|
pub struct Session {
  priv opc : @opc.Package
  priv mut encrypted_source : Bytes?
  priv main : String
  priv mut document : @xml.Document?
  priv mut parts : Map[String, @xml.Document]
  priv mut media : Map[String, Bytes]
  priv mut texts : Array[TextNode]
  priv mut selection : Selection?
  priv mut typing_text : Int32?
  priv mut typing_format : CharacterFormat?
  priv mut input_group : Int32?
  priv mut vertical_x : Double?
  priv mut navigation_layout : Int32
  priv history : Array[Edit]
  priv redo : Array[Edit]
  priv mut history_bytes : Int32
  priv mut revision : Int32
  priv mut flow_cache : FlowCache?
  priv mut composition : Composition?
  priv mut composition_id : Int32
  priv mut drawing_gesture : DrawingGesture?
  priv mut drawing_gesture_id : Int32
  priv mut tracking_context : (String, String)?
  priv mut closed : Bool
  priv diagnostics : Array[String]
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
  password? : String,
) -> Session raise @failure.Failure {
  if @archive.encrypted_office_streams(bytes, budget) is Some((info, payload)) {
    let maximum = budget.retained_bytes - bytes.length()
    let plain = if info.length() >= 4 && encryption_u32(info, 0) == 0x00040004U {
      decrypt_agile_office(info, payload, password, maximum, budget)
    } else {
      decrypt_standard_office(info, payload, password, maximum)
    }
    let session = Session::from_package(@opc.Package::open(plain, budget))
    session.encrypted_source = Some(bytes)
    return session
  }
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
    encrypted_source: None,
    main,
    document: Some(document),
    parts: Map([]),
    media: Map([]),
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
    flow_cache: None,
    composition: None,
    composition_id: 0,
    drawing_gesture: None,
    drawing_gesture_id: 0,
    tracking_context: None,
    closed: false,
    diagnostics,
  }
}

///|
pub fn Session::current_revision(
  self : Session,
) -> Int32 raise @failure.Failure {
  ignore(self.document())
  self.revision
}

///|
fn Session::document(self : Session) -> @xml.Document raise @failure.Failure {
  guard !self.closed && self.document is Some(document) else {
    @failure.reject("closed-session", "DOCX session is closed")
  }
  document
}

///|
#derive(ToJson)
priv struct QueryText {
  id : Int32
  paragraph : Int32
  run : Int32
  text : String
}

///|
#derive(ToJson)
priv struct QueryState {
  revision : Int32
  compositionId : Json
  mainPart : String
  texts : Array[QueryText]
  relationships : ReadOnlyArray[@opc.Relationship]
  diagnostics : Array[String]
  decodedBytes : Int32
}

///|
pub fn Session::query(self : Session) -> Json raise @failure.Failure {
  let document = self.display_document()
  let tree = WordTree::new(document)
  let nodes = tree.nodes
  let texts : Array[QueryText] = []
  for
    node in (if self.composition is Some(_) {
      docx_texts(tree)
    } else {
      self.texts
    }) {
    texts.push({
      id: node.id,
      paragraph: node.paragraph,
      run: node.run,
      text: inline_text(nodes[node.id]),
    })
  }
  let result : QueryState = {
    revision: self.revision,
    compositionId: self.composition
    .map(composition => Json(composition.id))
    .unwrap_or(Json::null()),
    mainPart: self.main,
    texts,
    relationships: self.relationships(),
    diagnostics: self.diagnostics,
    decodedBytes: self.opc.decoded_bytes(),
  }
  ToJson::to_json(result)
}

///|
pub fn Session::replace(
  self : Session,
  id : Int32,
  revision : Int32,
  text : String,
) -> Int32 raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  guard self.texts.iter().filter(node => node.id == id).next() is Some(node) else {
    @failure.reject("invalid-operation", "Unknown or unsupported text node")
  }
  let nodes = WordTree::new(document).nodes
  let texts = self.texts.filter(item => item.paragraph == node.paragraph)
  let before = inline_text(nodes[id])
  guard text.length() <= TextCommandUnits else {
    @failure.reject("limit-exceeded", "Command input exceeds UTF-16 budget")
  }
  if before == text && nodes[id].name != "drawing" {
    self.input_group = None
    return self.revision
  }
  let mut offset = 0
  for item in texts {
    if item.id == id {
      break
    }
    offset += inline_text(nodes[item.id]).length()
  }
  if self.tracking_context is Some(_) ||
    WordTree::new(document).has_review_markup(node.paragraph) {
    let start : Position = {
      paragraph: node.paragraph,
      offset,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
    ignore(
      self.replace_range(
        revision,
        {
          anchor: start,
          focus: { ..start, offset: offset + before.length(), },
        },
        text,
      ),
    )
    return self.revision
  }
  let after = self.selection.map(selection => {
    if selection.anchor.paragraph != node.paragraph &&
      selection.focus.paragraph != node.paragraph {
      return {
        anchor: { ..selection.anchor, frameStart: None, },
        focus: { ..selection.focus, frameStart: None, },
      }
    }
    let content = texts.map(item => inline_text(nodes[item.id])).join("")
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
  if self.encrypted_source is Some(bytes) {
    guard bytes.length() <= self.opc.budget.output_bytes else {
      @failure.reject("limit-exceeded", "Encrypted DOCX output exceeds budget")
    }
    for _, name in self.opc.names {
      ignore(self.opc.read(name))
    }
    return bytes
  }
  self.opc.save(self.replacements(document, self.parts))
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.tracking_context = None
  self.composition = None
  self.drawing_gesture = None
  self.opc.close()
  self.encrypted_source = None
  self.document = None
  self.flow_cache = None
  self.parts.clear()
  self.media.clear()
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
