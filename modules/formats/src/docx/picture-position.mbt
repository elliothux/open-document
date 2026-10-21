///|
fn picture_axis_markup(axis : @layout.DrawingAxis, name : String) -> String {
  let (reference, value) = match axis {
    @layout.Offset(reference, value) =>
      (
        reference,
        "<wp:posOffset>\{(value * 12700).round().to_int64()}</wp:posOffset>",
      )
    @layout.Aligned(reference, value) =>
      (reference, "<wp:align>\{value}</wp:align>")
  }
  "<wp:\{name} xmlns:wp=\"\{picture_inline_uri}\" relativeFrom=\"\{reference}\">\{value}</wp:\{name}>"
}

///|
fn rounded_image_anchor(
  anchor : @layout.DrawingAnchor,
) -> @layout.DrawingAnchor {
  let round = fn(axis : @layout.DrawingAxis) {
    match axis {
      @layout.Offset(reference, value) =>
        @layout.Offset(reference, (value * 12700).round() / 12700)
      aligned => aligned
    }
  }
  {
    ..anchor,
    horizontal: round(anchor.horizontal),
    vertical: round(anchor.vertical),
    distance: {
      top: (anchor.distance.top * 12700).round() / 12700,
      right: (anchor.distance.right * 12700).round() / 12700,
      bottom: (anchor.distance.bottom * 12700).round() / 12700,
      left: (anchor.distance.left * 12700).round() / 12700,
    },
  }
}

///|
/// Changes ordinary body picture placement and supported wrapping.
/// An explicit target reanchors a floating picture and selects its new logical range.
/// Target offsets refer to the current document before removing the picture.
pub fn Session::set_picture_anchor(
  self : Session,
  revision : Int,
  id : Int,
  anchor : @layout.DrawingAnchor?,
  target? : Position,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let prepared = self.prepare_picture_anchor(
    id,
    anchor,
    target?,
    probe?,
    profile~,
    images?,
  )
  if prepared is Some(prepared) {
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.edit_result(prepared.map(value => value.edit.paragraphs).unwrap_or([]))
}

///|
fn Session::prepare_picture_placement(
  self : Session,
  id : Int,
  anchor : @layout.DrawingAnchor?,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> PreparedEdit? raise @failure.Failure {
  if anchor is Some(anchor) {
    anchor.validate()
  }
  let anchor = anchor.map(rounded_image_anchor)
  let document = self.document()
  let tree = WordTree::new(document)
  let (image, paragraph, _, _) = self.editable_picture(tree, id, position=true)
  if Json(image.anchor.map(value => value.to_json())) ==
    Json(anchor.map(value => value.to_json())) {
    return None
  }
  if anchor is Some(_) {
    for parent = tree.nodes[paragraph].parent
        parent >= 0
        parent = tree.nodes[parent].parent {
      guard tree.nodes[parent].name != "tc" else {
        @failure.reject(
          "protected-content", "Floating pictures require a body paragraph",
        )
      }
    }
  }
  guard tree.children[id] is [frame] else {
    @failure.reject("protected-content", "Picture requires one frame")
  }
  let node = tree.nodes[frame]
  guard !node.empty &&
    node.attributes.all(attr => {
      (
        attr.uri.is_empty() &&
        [
          "distT", "distB", "distL", "distR", "simplePos", "relativeHeight", "behindDoc",
          "locked", "layoutInCell", "allowOverlap",
        ].contains(attr.name)
      ) ||
      (
        anchor is Some(_) &&
        attr.uri ==
        "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" &&
        ["anchorId", "editId"].contains(attr.name)
      )
    }) else {
    @failure.reject(
      "protected-content", "Unknown picture frame metadata prevents placement changes",
    )
  }
  tree.anchor_children(frame, [
    "simplePos", "positionH", "positionV", "extent", "effectExtent", "docPr", "cNvGraphicFramePr",
    "wrapNone", "wrapTopAndBottom", "wrapSquare", "graphic",
  ])
  let changes : Array[@xml.SourceChange] = []
  let source = document.source()
  let name = if anchor is Some(_) { "anchor" } else { "inline" }
  let prefix = node.qualified[:node.qualified.length() - node.name.length()].to_owned()
  let qualified = prefix + name
  for
    (offset, length, xml) in [
      (1, node.qualified.length(), qualified),
      (node.closing_start - node.start + 2, node.qualified.length(), qualified),
    ] {
    changes.push({ node: frame, offset, length, xml, })
  }
  // Keep namespace declarations and every untouched source gap in the original opening tag.
  for attr in node.attributes {
    if attr.uri.is_empty() &&
      ["distT", "distB", "distL", "distR"].contains(attr.name) &&
      anchor is Some(anchor) {
      let value = match attr.name {
        "distT" => anchor.distance.top
        "distB" => anchor.distance.bottom
        "distL" => anchor.distance.left
        _ => anchor.distance.right
      }
      let original = @string.parse_int64(attr.value[:]) catch {
        _ => @failure.reject("invalid-image", "Invalid picture text distance")
      }
      if original != (value * 12700).round().to_int64() {
        changes.push({
          node: frame,
          offset: attr.start - node.start,
          length: attr.end - attr.start,
          xml: (value * 12700).round().to_int64().to_string(),
        })
      }
    }
    if attr.uri.is_empty() &&
      !["distT", "distB", "distL", "distR"].contains(attr.name) {
      let mut start = attr.start - 1
      while start > node.start && source[start] != '=' {
        start -= 1
      }
      start -= 1
      while start > node.start &&
            [32, 9, 10, 13].contains(source[start].to_int()) {
        start -= 1
      }
      while start > node.start &&
            ![32, 9, 10, 13].contains(source[start].to_int()) {
        start -= 1
      }
      changes.push({
        node: frame,
        offset: start - node.start,
        length: attr.end + 1 - start,
        xml: "",
      })
    }
  }
  let attributes = anchor
    .map(value => {
      let distances = StringBuilder()
      for
        (key, number) in [
          ("distT", value.distance.top),
          ("distB", value.distance.bottom),
          ("distL", value.distance.left),
          ("distR", value.distance.right),
        ] {
        if node.attribute(key) is None &&
          (number != 0 || key == "distL" || key == "distR") {
          distances.write_string(
            " \{key}=\"\{(number * 12700).round().to_int64()}\"",
          )
        }
      }
      " simplePos=\"0\" relativeHeight=\"\{value.order}\" behindDoc=\"\{if value.behind { "1" } else { "0" }}\" locked=\"\{node.attribute("locked").unwrap_or("0")}\" layoutInCell=\"\{node.attribute("layoutInCell").unwrap_or("1")}\" allowOverlap=\"1\"" +
      distances.to_string()
    })
    .unwrap_or("")
  changes.push({
    node: frame,
    offset: node.opening_end - node.start - 1,
    length: 0,
    xml: attributes,
  })
  for child in tree.children[frame] {
    let current = tree.nodes[child]
    if [
        "simplePos", "positionH", "positionV", "wrapNone", "wrapTopAndBottom", "wrapSquare",
      ].contains(current.name) {
      let raw = source[current.start:current.end]
      guard !raw.contains("<!--") && !raw.contains("<?") else {
        @failure.reject(
          "protected-content", "Picture position contains opaque markup",
        )
      }
      changes.push({
        node: frame,
        offset: current.start - node.start,
        length: current.end - current.start,
        xml: "",
      })
    }
  }
  if anchor is Some(anchor) {
    let extent = tree.nodes[tree.anchor_child(frame, "extent")]
    changes.push({
      node: frame,
      offset: extent.start - node.start,
      length: 0,
      xml: "<wp:simplePos xmlns:wp=\"\{picture_inline_uri}\" x=\"0\" y=\"0\"/>" +
      picture_axis_markup(anchor.horizontal, "positionH") +
      picture_axis_markup(anchor.vertical, "positionV"),
    })
    let props = tree.nodes[tree.anchor_child(frame, "docPr")]
    changes.push({
      node: frame,
      offset: props.start - node.start,
      length: 0,
      xml: if anchor.wrapping == "square" {
        "<wp:wrapSquare xmlns:wp=\"\{picture_inline_uri}\" wrapText=\"\{anchor.wrapSide}\"/>"
      } else {
        "<wp:\{if anchor.wrapping == "none" { "wrapNone" } else { "wrapTopAndBottom" }} xmlns:wp=\"\{picture_inline_uri}\"/>"
      },
    })
  }
  let (candidate, xml) = document.edit_source(changes)
  ignore(self.image_frame(WordTree::new(candidate), id))
  self.check_picture_layout(candidate, probe, profile, images)
  Some({
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  })
}
