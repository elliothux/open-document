///|
fn background_image_properties(
  properties : Ref,
  image : Ref,
) -> Unit raise @failure.Failure {
  guard properties.tree.children
    .get(properties.node.id)
    .unwrap_or([])
    .all(node => {
      node.id == image.node.id ||
      (
        node.uri == drawing_uri &&
        node.name == "effectLst" &&
        node.attributes.is_empty() &&
        node.text.trim().is_empty() &&
        properties.tree.children.get(node.id).unwrap_or([]).is_empty()
      )
    }) else {
    @failure.reject(
      "unsupported-style", "Unsupported image background properties",
    )
  }
}

///|
fn background_image_source(slide : Slide) -> Ref? raise @failure.Failure {
  let tree = slide.tree
  let container = tree.required(
    tree.root("sld").id,
    "cSld",
    uri=presentation_uri,
  )
  tree
  .one(container.id, "bg", uri=presentation_uri)
  .bind(bg => tree.one(bg.id, "bgPr", uri=presentation_uri))
  .bind(p => tree.one(p.id, "blipFill"))
  .map(node => { tree, node, })
}

///|
fn Session::set_background_image_format(
  self : Session,
  index : Int,
  mode : String,
  crop : Array[Double],
  opacity : Double,
) -> Json raise @failure.Failure {
  check_image_fill_mode(mode)
  let crop = normalized_image_crop(crop)
  let opacity = image_opacity_amount(opacity).to_double() / 100000
  let slide = self.slides[index]
  let reason = self.background_reason(slide)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let background = slide.background
  guard background is Picture(key, _, _, _) else {
    @failure.reject(
      "invalid-operation", "Set a picture background before changing its format",
    )
  }
  self.write_image(
    self.image_bytes(key),
    None,
    background=Some(index),
    mode~,
    background_format=Some((crop, opacity)),
  )
}

///|
fn Slide::image_keys(self : Slide) -> Array[String] {
  let keys = if self.background is Picture(key, _, _, _) { [key] } else { [] }
  for object in self.objects {
    if object.image is Some(key) && !keys.contains(key) {
      keys.push(key)
    }
  }
  keys
}

///|
fn background_change(
  original : Slide,
  fill : String?,
) -> @xml.SourceChange raise @failure.Failure {
  let tree = original.tree
  let container = tree.required(
    tree.root("sld").id,
    "cSld",
    uri=presentation_uri,
  )
  let background = tree.one(container.id, "bg", uri=presentation_uri)
  let markup = if fill is Some(fill) {
    let bw = background
      .bind(bg => bg.attribute("bwMode"))
      .map(v => " bwMode=\"\{xml_attribute(v)}\"")
      .unwrap_or("")
    let shade = background
      .bind(bg => tree.one(bg.id, "bgPr", uri=presentation_uri))
      .bind(p => p.attribute("shadeToTitle"))
      .map(v => " shadeToTitle=\"\{xml_attribute(v)}\"")
      .unwrap_or("")
    "<p:bg xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"\{bw}><p:bgPr\{shade}>\{fill}</p:bgPr></p:bg>"
  } else {
    ""
  }
  {
    node: container.id,
    offset: background.map(bg => bg.start).unwrap_or(container.opening_end) -
    container.start,
    length: background.map(bg => bg.end - bg.start).unwrap_or(0),
    xml: markup,
  }
}
