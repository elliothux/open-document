///|
fn Tree::drawing_rect(
  self : Tree,
  frame : @xml.Node,
  dimensions : Dimensions,
) -> (String, @layout.Border) raise @failure.Failure {
  let anchor = if frame.name == "absoluteAnchor" {
    "fixed"
  } else if frame.name == "oneCellAnchor" {
    "move"
  } else {
    guard frame.attribute("editAs").unwrap_or("twoCell") == "twoCell" else {
      @failure.reject(
        "unsupported-drawing", "This two-cell edit policy requires anchor normalization",
      )
    }
    "size"
  }
  let (x, y) = if anchor == "fixed" {
    let pos = self.picture_node(frame.id, "pos")
    (
      picture_integer(pos.attribute("x").unwrap_or("")) / 12700,
      picture_integer(pos.attribute("y").unwrap_or("")) / 12700,
    )
  } else {
    self.picture_mark(frame.id, "from", dimensions)
  }
  let (width, height) = if anchor == "size" {
    let (right, bottom) = self.picture_mark(frame.id, "to", dimensions)
    (right - x, bottom - y)
  } else {
    let ext = self.picture_node(frame.id, "ext")
    (
      picture_integer(ext.attribute("cx").unwrap_or("")) / 12700,
      picture_integer(ext.attribute("cy").unwrap_or("")) / 12700,
    )
  }
  guard x >= 0 &&
    y >= 0 &&
    width >= 0 &&
    height >= 0 &&
    width <= 14400 &&
    height <= 14400 &&
    x + width <= dimensions.columns.position(16385) &&
    y + height <= dimensions.rows.position(1048577) else {
    @failure.reject(
      "limit-exceeded", "Worksheet object exceeds sheet or drawing bounds",
    )
  }
  (anchor, { x, y, width, height, })
}
