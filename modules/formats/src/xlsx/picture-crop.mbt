///|
fn checked_picture_crop(
  crop : Array[Double],
  rect : @layout.Border,
) -> Array[Double] raise @failure.Failure {
  guard crop.length() == 4 &&
    crop.all(value => {
      !value.is_nan() && !value.is_inf() && value >= 0 && value < 1
    }) else {
    @failure.reject("invalid-operation", "Invalid worksheet picture crop")
  }
  let crop = crop.map(value => (value * 100000).round() / 100000)
  guard crop[0] + crop[2] < 1 && crop[1] + crop[3] < 1 else {
    @failure.reject(
      "invalid-operation", "Picture crop removes its entire source",
    )
  }
  guard rect.width / (1 - crop[0] - crop[2]) <= 1000000000 &&
    rect.height / (1 - crop[1] - crop[3]) <= 1000000000 else {
    @failure.reject(
      "limit-exceeded", "Expanded worksheet picture exceeds drawing budget",
    )
  }
  crop
}

///|
fn SheetObject::crop_changes(
  self : SheetObject,
  crop : Array[Double],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if self.crop == crop {
    return []
  }
  let tree = self.tree
  let fill = tree.picture_node(self.source.id, "blipFill")
  let existing = tree.picture_child(fill.id, "srcRect", uri=picture_drawing_uri)
  if existing is Some(node) {
    guard node.attributes.all(attribute => {
        attribute.uri.is_empty() &&
        ["l", "t", "r", "b"].contains(attribute.name)
      }) &&
      tree.children.get(node.id).unwrap_or([]).is_empty() &&
      (
        node.empty ||
        tree.document.source()[node.opening_end:node.closing_start]
        .trim()
        .is_empty()
      ) else {
      @failure.reject(
        "protected-content", "Unknown worksheet picture crop metadata",
      )
    }
  }
  let markup = if crop.all(value => value == 0) {
    ""
  } else {
    let values = ["l", "t", "r", "b"]
      .mapi((index, name) => {
        " \{name}=\"\{(crop[index] * 100000).round().to_int()}\""
      })
      .join("")
    "<odA:srcRect xmlns:odA=\"\{picture_drawing_uri}\"\{values}/>"
  }
  [
    {
      node: fill.id,
      offset: existing
      .map(node => node.start)
      .unwrap_or_else(() => {
        tree.picture_node(fill.id, "stretch", uri=picture_drawing_uri).start
      }) -
      fill.start,
      length: existing.map(node => node.end - node.start).unwrap_or(0),
      xml: markup,
    },
  ]
}
