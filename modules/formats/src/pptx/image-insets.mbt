///|
fn read_image_insets(fill : Ref) -> Array[Double] raise @failure.Failure {
  let stretch = fill.child("stretch")
  guard stretch is Some(stretch) else { return [0, 0, 0, 0] }
  let children = stretch.tree.children.get(stretch.node.id).unwrap_or([])
  guard stretch.node.attributes.is_empty() &&
    children.length() <= 1 &&
    children.all(node => {
      node.uri == drawing_uri &&
      node.name == "fillRect" &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() && ["l", "t", "r", "b"].contains(a.name)
      }) &&
      stretch.tree.children.get(node.id).unwrap_or([]).is_empty()
    }) else {
    @failure.reject("unsupported-style", "Unknown image destination metadata")
  }
  let values = children
    .get(0)
    .map(node => {
      ["l", "t", "r", "b"].map(key => {
        number(node.attribute(key).unwrap_or("0"), -2147483648, 2147483647) /
        100000
      })
    })
    .unwrap_or([0, 0, 0, 0])
  guard values[0] + values[2] < 1 && values[1] + values[3] < 1 else {
    @failure.reject(
      "unsupported-style", "Image destination must retain positive area",
    )
  }
  values
}

///|
fn normalized_image_insets(
  values : Array[Double],
) -> Array[Double] raise @failure.Failure {
  guard values.length() == 4 &&
    values.all(value => {
      !value.is_nan() &&
      !value.is_inf() &&
      value >= -21474.83648 &&
      value <= 21474.83647
    }) else {
    @failure.reject("invalid-operation", "Invalid image destination insets")
  }
  let values = values.map(value => (value * 100000).round() / 100000)
  guard values[0] + values[2] < 1 && values[1] + values[3] < 1 else {
    @failure.reject(
      "invalid-operation", "Image destination must retain positive area",
    )
  }
  values
}

///|
fn image_insets_markup(insets : Array[Double]) -> String {
  "<a:fillRect xmlns:a=\"\{drawing_uri}\" l=\"\{(insets[0]*100000).round().to_int64()}\" t=\"\{(insets[1]*100000).round().to_int64()}\" r=\"\{(insets[2]*100000).round().to_int64()}\" b=\"\{(insets[3]*100000).round().to_int64()}\"/>"
}

///|
fn image_insets_change(
  fill : Ref,
  insets : Array[Double],
) -> @xml.SourceChange raise @failure.Failure {
  let markup = image_insets_markup(insets)
  if fill.child("stretch") is Some(stretch) {
    paint_child_change(
      stretch,
      stretch.child("fillRect").map(item => item.node),
      markup,
      [],
    )
  } else {
    paint_child_change(
      fill,
      None,
      "<a:stretch xmlns:a=\"\{drawing_uri}\">\{markup}</a:stretch>",
      ["extLst"],
    )
  }
}

///|
fn stretched_image(
  key : String,
  width : Double,
  height : Double,
  crop : Array[Double],
  insets : Array[Double],
  opacity : Double,
) -> Array[@layout.PositionedPrimitive] {
  let x = width * insets[0]
  let y = height * insets[1]
  let target_width = width * (1 - insets[0] - insets[2])
  let target_height = height * (1 - insets[1] - insets[3])
  let w = target_width / (1 - crop[0] - crop[2])
  let h = target_height / (1 - crop[1] - crop[3])
  let result : Array[@layout.PositionedPrimitive] = []
  if insets.any(value => value != 0) {
    result.push(Clip({ x, y, width: target_width, height: target_height, }))
  }
  result.push(
    Image(
      { key, x: x - crop[0] * w, y: y - crop[1] * h, width: w, height: h, },
      opacity,
    ),
  )
  if insets.any(value => value != 0) {
    result.push(Restore)
  }
  result
}

///|
fn Session::image_insets_reason(self : Session, object : Object) -> String {
  let reason = if object.kind == "image" {
    self.image_mode_reason(object)
  } else {
    self.image_fill_reason(object)
  }
  if !reason.is_empty() {
    return reason
  }
  if object.image is None || object.tile is Some(_) {
    return "Image destination insets require a stretched image"
  }
  if object.kind != "image" &&
    !object.fill_source
    .map(source => source.0.tree.part == object.source.tree.part)
    .unwrap_or(false) {
    return "Set a local image fill before changing its destination"
  }
  ""
}

///|
fn Session::set_image_insets(
  self : Session,
  values : Array[Double],
) -> Json raise @failure.Failure {
  let insets = normalized_image_insets(values)
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Select pictures or image-filled shapes",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.image_insets_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let geometry = object.geometry.unwrap()
    check_image_crop_bounds(
      geometry.width,
      geometry.height,
      object.crop,
      insets~,
    )
    if object.insets == insets {
      continue
    }
    let fill = if object.kind == "image" {
      object.source.child("blipFill", uri=presentation_uri).unwrap()
    } else {
      object.fill_source.unwrap().0
    }
    changes.push(image_insets_change(fill, insets))
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare(self.current(), changes)
  self.commit(candidate, edit, self.selection)
  self.query()
}
