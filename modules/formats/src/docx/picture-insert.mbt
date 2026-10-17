///|
fn Session::next_picture_identity(self : Session) -> Int raise @failure.Failure {
  let documents = [self.document()]
  for rel in self.relationships() {
    if !rel.external &&
      [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer",
      ].contains(rel.kind) {
      documents.push(self.part_xml(rel.target))
    }
  }
  let used : Map[String, Bool] = Map([])
  for document in documents {
    for node in document.nodes() {
      if node.name == "docPr" || node.name == "cNvPr" {
        if node.attribute("id") is Some(value) {
          used[picture_identity(value)] = true
        }
      }
    }
  }
  for id = 1; id <= 16384; id = id + 1 {
    if !used.contains(id.to_string()) {
      return id
    }
  }
  @failure.reject("limit-exceeded", "Picture identities exhausted")
}

///|
pub fn Session::insert_picture(
  self : Session,
  revision : Int,
  width : Double,
  height : Double,
  bytes : Bytes,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  guard [width, height].all(value => {
    !value.is_nan() && !value.is_inf() && value >= 0.1 && value <= 14400
  }) else {
    @failure.reject("invalid-operation", "Invalid picture dimensions")
  }
  let original = self.document()
  let tree = WordTree::new(original)
  self.check_picture_context(tree)
  let range = self.paragraph_range(tree, selection, structural=true)
  guard tree.order
    .filter(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing"
    })
    .length() <
    256 else {
    @failure.reject("limit-exceeded", "Picture list exceeds 256 entries")
  }
  let kind = @image.type_info(bytes)
  let identity = self.next_picture_identity()
  let prepared = if range.start.paragraph == range.end.paragraph {
    self.prepare_plain_range(selection, "")
  } else {
    Some(self.prepare_structural_range(selection, ""))
  }
  let document = prepared.map(edit => edit.document).unwrap_or(original)
  let position = prepared
    .bind(edit => edit.edit.after)
    .map(value => value.focus)
    .unwrap_or(range.start)
  let xml = prepared.map(edit => edit.edit.xml.copy()).unwrap_or([])
  let paragraphs = prepared
    .map(edit => edit.edit.paragraphs.copy())
    .unwrap_or([position.paragraph])
  let resource = self.prepare_picture_resource(
    identity,
    bytes,
    (kind.0, kind.1),
  )
  let tree = WordTree::new(document)
  let texts = docx_texts(tree).filter(item => {
    item.paragraph == position.paragraph
  })
  let target = for item in texts; offset = 0 {
    let length = inline_text(tree.nodes[item.id]).length()
    if position.offset < offset + length ||
      (position.offset == offset + length && position.affinity == "before") {
      break Some((item.id, position.offset - offset))
    }
    continue offset + length
  } nobreak {
    texts
    .last()
    .map(item => (item.id, inline_text(tree.nodes[item.id]).length()))
  }
  let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let picture = "http://schemas.openxmlformats.org/drawingml/2006/picture"
  let cx = (width * 12700).round().to_int64().to_string()
  let cy = (height * 12700).round().to_int64().to_string()
  let drawing = "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:pic=\"\{picture}\" xmlns:r=\"\{rel}\"><wp:inline><wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:docPr id=\"\{identity}\" name=\"Picture \{identity}\"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri=\"\{picture}\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\{identity}\" name=\"Picture \{identity}\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\{resource.link}\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></od:drawing>"
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let change : @xml.SourceChange = if target is Some((id, offset)) {
    let node = tree.nodes[id]
    guard tree.nodes[node.parent].parent == position.paragraph else {
      @failure.reject(
        "protected-content", "Picture insertion inside hyperlinks requires editing support",
      )
    }
    if node.name == "drawing" {
      let parent = tree.nodes[node.parent]
      {
        node: parent.id,
        offset: (if offset == 0 { node.start } else { node.end }) - parent.start,
        length: 0,
        xml: drawing,
      }
    } else {
      guard node.attributes.all(attr => {
          (
            node.name == "t" &&
            attr.uri == "http://www.w3.org/XML/1998/namespace" &&
            attr.name == "space"
          ) ||
          (
            node.name == "br" &&
            attr.uri == word_uri &&
            ["type", "clear"].contains(attr.name)
          )
        }) &&
        !document.source()[node.start:node.end].contains("<!--") &&
        !document.source()[node.start:node.end].contains("<?") else {
        @failure.reject(
          "protected-content", "Unknown inline source prevents picture insertion",
        )
      }
      let text = inline_text(node)
      let markup = inline_markup(text[:offset].to_owned(), limit) +
        drawing +
        inline_markup(text[offset:].to_owned(), limit)
      guard markup.length() <= limit else {
        @failure.reject(
          "limit-exceeded", "Picture insertion source exceeds budget",
        )
      }
      let parent = tree.nodes[node.parent]
      {
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: markup,
      }
    }
  } else {
    let run = tree.child(position.paragraph, "r")
    let parent = tree.nodes[run.unwrap_or(position.paragraph)]
    let markup = if run is Some(_) {
      drawing
    } else {
      "<od:r xmlns:od=\"\{word_uri}\">" +
      tree.empty_run_properties(document, position.paragraph) +
      drawing +
      "</od:r>"
    }
    if parent.empty {
      {
        node: parent.id,
        offset: parent.opening_end - parent.start - 2,
        length: 2,
        xml: ">" + markup + "</" + parent.qualified + ">",
      }
    } else {
      {
        node: parent.id,
        offset: parent.closing_start - parent.start,
        length: 0,
        xml: markup,
      }
    }
  }
  let (candidate, step) = document.edit_source([change])
  xml.push(step)
  let text = docx_texts(WordTree::new(candidate))
    .filter(item => item.paragraph == position.paragraph)
    .map(item => inline_text(candidate.node(item.id)))
    .join("")
  let caret = {
    ..position,
    offset: editing_boundaries(text, true)
    .iter()
    .find_first(value => value >= position.offset + 1)
    .unwrap(),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  self.commit_picture_resource(
    resource,
    candidate,
    xml,
    paragraphs,
    Some({ anchor: caret, focus: caret, }),
  )
}
