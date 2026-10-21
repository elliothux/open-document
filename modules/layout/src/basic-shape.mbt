///|
/// Builds the shared rectangle, ellipse or diagonal-line outline in local points.
pub fn basic_shape_path(
  preset : String,
  width : Double,
  height : Double,
) -> Array[PathSegment] {
  if preset == "line" {
    return [Move(0, 0), Line(width, height)]
  }
  if preset == "ellipse" {
    let k = 0.5522847498307936
    let x = width / 2
    let y = height / 2
    return [
      Move(width, y),
      Cubic(width, y + k * y, x + k * x, height, x, height),
      Cubic(x - k * x, height, 0, y + k * y, 0, y),
      Cubic(0, y - k * y, x - k * x, 0, x, 0),
      Cubic(x + k * x, 0, width, y - k * y, width, y),
      Close,
    ]
  }
  [Move(0, 0), Line(width, 0), Line(width, height), Line(0, height), Close]
}
