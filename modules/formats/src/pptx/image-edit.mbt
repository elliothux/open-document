///|
fn Session::image_reason(
  self : Session,
  object : Object,
  crop : Bool,
) -> String {
  if !object.read_only.is_empty() {
    return object.read_only
  }
  try {
    guard object.kind == "image" &&
      object.image is Some(_) &&
      object.source.tree.part == self.selection.slide &&
      object.parent.is_empty() &&
      object.source.node.parent == shape_tree(self.current().tree).id else {
      return "Picture editing requires a local top-level picture"
    }
    let fill = object.source.child("blipFill", uri=presentation_uri).unwrap()
    guard fill.child("blip") is Some(blip) &&
      blip.node.attribute("embed", uri=relationship_uri) is Some(_) &&
      blip.node.attribute("link", uri=relationship_uri) is None else {
      return "Picture editing requires one embedded image"
    }
    if crop {
      for node in object.source.tree.document.nodes() {
        if node.start >= object.source.node.start &&
          node.end <= object.source.node.end &&
          node.name.has_suffix("Locks") &&
          flag(node, "noCrop") {
          return "Picture cropping is locked"
        }
      }
      if fill.child("srcRect") is Some(rect) {
        guard rect.node.attributes.all(a => {
            a.uri.is_empty() && ["l", "t", "r", "b"].contains(a.name)
          }) &&
          rect.node.text.trim().is_empty() &&
          rect.tree.children.get(rect.node.id).unwrap_or([]).is_empty() &&
          !source_xml(rect).contains("<!--") &&
          !source_xml(rect).contains("<?") else {
          return "Unknown crop markup is protected"
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::selected_image(
  self : Session,
  crop : Bool,
) -> Object raise @failure.Failure {
  let object = self.editable(false)
  let reason = self.image_reason(object, crop)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  object
}

///|
fn Session::crop_image(
  self : Session,
  crop : Array[Double],
) -> Json raise @failure.Failure {
  guard crop.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v < 1) else {
    @failure.reject("invalid-operation", "Invalid picture crop")
  }
  let values = crop.map(v => (v * 100000).round().to_int())
  guard values[0] + values[2] < 100000 && values[1] + values[3] < 100000 else {
    @failure.reject(
      "invalid-operation", "Picture crop must retain a positive source area",
    )
  }
  let object = self.selected_image(true)
  if object.crop.map(v => (v * 100000).round().to_int()) == values {
    return self.query()
  }
  let geometry = object.geometry.unwrap()
  guard geometry.width / (1 - (values[0] + values[2]).to_double() / 100000) <=
    1000000000.0 &&
    geometry.height / (1 - (values[1] + values[3]).to_double() / 100000) <=
    1000000000.0 else {
    @failure.reject("limit-exceeded", "Cropped picture exceeds drawing bounds")
  }
  let fill = object.source.child("blipFill", uri=presentation_uri).unwrap()
  let markup = if values.all(v => v == 0) {
    ""
  } else {
    "<a:srcRect xmlns:a=\"\{drawing_uri}\" l=\"\{values[0]}\" t=\"\{values[1]}\" r=\"\{values[2]}\" b=\"\{values[3]}\"/>"
  }
  let change = paint_child_change(
    fill,
    fill.child("srcRect").map(item => item.node),
    markup,
    ["tile", "stretch", "extLst"],
  )
  let (slide, edit) = self.prepare(self.current(), [change])
  self.commit(slide, edit, self.selection)
  self.query()
}
