///|
fn Session::image_reason(
  self : Session,
  object : Object,
  crop : Bool,
) -> String {
  let reason = self.appearance_reason(object)
  if !reason.is_empty() {
    return reason
  }
  try {
    guard object.kind == "image" &&
      object.image is Some(_) &&
      object.source.tree.part == self.selection.slide else {
      return "Picture editing requires a local picture"
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
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Picture editing requires one selected object",
    )
  }
  let object = self.current().object(self.selection.object)
  let reason = self.image_reason(object, crop)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  object
}

///|
fn normalized_image_crop(
  crop : Array[Double],
) -> Array[Double] raise @failure.Failure {
  guard crop.length() == 4 &&
    crop.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v < 1) else {
    @failure.reject("invalid-operation", "Invalid picture crop")
  }
  let values = crop.map(v => (v * 100000).round().to_int())
  guard values[0] + values[2] < 100000 && values[1] + values[3] < 100000 else {
    @failure.reject(
      "invalid-operation", "Picture crop must retain a positive source area",
    )
  }
  values.map(v => v.to_double() / 100000)
}

///|
fn image_crop_change(
  fill : Ref,
  crop : Array[Double],
) -> @xml.SourceChange raise @failure.Failure {
  let values = crop.map(v => (v * 100000).round().to_int())
  let markup = if values.all(v => v == 0) {
    ""
  } else {
    "<a:srcRect xmlns:a=\"\{drawing_uri}\" l=\"\{values[0]}\" t=\"\{values[1]}\" r=\"\{values[2]}\" b=\"\{values[3]}\"/>"
  }
  paint_child_change(
    fill,
    fill.child("srcRect").map(item => item.node),
    markup,
    ["tile", "stretch", "extLst"],
  )
}

///|
fn check_image_crop_bounds(
  width : Double,
  height : Double,
  crop : Array[Double],
  insets~ : Array[Double] = [0, 0, 0, 0],
) -> Unit raise @failure.Failure {
  let w = width * (1 - insets[0] - insets[2]) / (1 - crop[0] - crop[2])
  let h = height * (1 - insets[1] - insets[3]) / (1 - crop[1] - crop[3])
  guard w <= 1000000000.0 &&
    h <= 1000000000.0 &&
    (width * insets[0] - crop[0] * w).abs() <= 1000000000.0 &&
    (height * insets[1] - crop[1] * h).abs() <= 1000000000.0 else {
    @failure.reject("limit-exceeded", "Cropped picture exceeds drawing bounds")
  }
}

///|
fn Session::crop_image(
  self : Session,
  crop : Array[Double],
) -> Json raise @failure.Failure {
  let crop = normalized_image_crop(crop)
  let object = self.selected_image(true)
  if object.crop == crop {
    return self.query()
  }
  let geometry = object.geometry.unwrap()
  if object.tile is None {
    check_image_crop_bounds(
      geometry.width,
      geometry.height,
      crop,
      insets=object.insets,
    )
  }
  let fill = object.source.child("blipFill", uri=presentation_uri).unwrap()
  let change = image_crop_change(fill, crop)
  let (slide, edit) = self.prepare(self.current(), [change])
  self.commit(slide, edit, self.selection)
  self.query()
}
