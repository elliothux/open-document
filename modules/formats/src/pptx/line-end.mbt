///|
pub(all) struct LineEnd {
  kind : String
  width : String
  length : String
} derive(Eq, ToJson)

///|
pub extend LineEnd with Eq::{equal, not_equal}

///|
pub extend LineEnd with ToJson::{to_json}

///|
fn no_line_end() -> LineEnd {
  { kind: "none", width: "med", length: "med", }
}

///|
fn LineEnd::validate(self : LineEnd) -> Unit raise @failure.Failure {
  guard ["none", "triangle", "stealth", "diamond", "oval", "arrow"].contains(
      self.kind,
    ) &&
    ["sm", "med", "lg"].contains(self.width) &&
    ["sm", "med", "lg"].contains(self.length) else {
    @failure.reject("unsupported-style", "Unknown DrawingML line end")
  }
}

///|
fn line_end(
  lines : Array[Ref],
  name : String,
) -> LineEnd raise @failure.Failure {
  for line in lines {
    let nodes = line.tree.children
      .get(line.node.id)
      .unwrap_or([])
      .filter(n => n.uri == drawing_uri && n.name == name)
    guard nodes.length() <= 1 else {
      @failure.reject("unsupported-style", "Duplicate line ends")
    }
    if nodes.get(0) is Some(node) {
      guard node.text.trim().is_empty() &&
        line.tree.children.get(node.id).unwrap_or([]).is_empty() &&
        node.attributes.all(a => {
          a.uri.is_empty() && ["type", "w", "len"].contains(a.name)
        }) else {
        @failure.reject("unsupported-style", "Unknown line end markup")
      }
      let result : LineEnd = {
        kind: node.attribute("type").unwrap_or("none"),
        width: node.attribute("w").unwrap_or("med"),
        length: node.attribute("len").unwrap_or("med"),
      }
      result.validate()
      return result
    }
  }
  no_line_end()
}

///|
fn LineEnd::size(self : LineEnd, pen : Double) -> (Double, Double) {
  let factor = fn(value) {
    if value == "sm" {
      2.0
    } else if value == "lg" {
      5.0
    } else {
      3.0
    }
  }
  // ONLYOFFICE's 2.5 px minimum is 1.875 pt at the SDK's fixed source scale.
  (pen.max(1.875) * factor(self.length), pen.max(1.875) * factor(self.width))
}

///|
fn Object::line_end_matrix(
  self : Object,
  geometry : Geometry,
  head : Bool,
) -> @layout.Matrix? {
  let points = self.line_points()
  let end = if head { points[0] } else { points.last().unwrap() }
  for
    point in (if head {
      points[1:].to_owned()
    } else {
      points[:points.length() - 1].rev()
    }) {
    let vx = (point.0 - end.0) * geometry.width
    let vy = (point.1 - end.1) * geometry.height
    let length = (vx * vx + vy * vy).sqrt()
    if length == 0 {
      continue
    }
    let dx = vx / length
    let dy = vy / length
    return Some({
      a: dx,
      b: dy,
      c: dy,
      d: -dx,
      e: end.0 * geometry.width,
      f: end.1 * geometry.height,
    })
  }
  None
}

///|
fn LineEnd::points(self : LineEnd, pen : Double) -> Array[(Double, Double)] {
  let (length, width) = self.size(pen)
  let half = width / 2
  match self.kind {
    "triangle" | "arrow" => [(length, half), (0.0, 0.0), (length, -half)]
    "stealth" =>
      [(length, half), (0.0, 0.0), (length, -half), (length - half, 0.0)]
    "diamond" =>
      [(length / 2, 0.0), (0.0, half), (-length / 2, 0.0), (0.0, -half)]
    _ => []
  }
}

///|
fn LineEnd::path(self : LineEnd, pen : Double) -> Array[@layout.PathSegment] {
  if self.kind == "oval" {
    let (length, width) = self.size(pen)
    let x = length / 2
    let y = width / 2
    let k = 0.5522847498307936
    return [
      Move(x, 0),
      Cubic(x, k * y, k * x, y, 0, y),
      Cubic(-k * x, y, -x, k * y, -x, 0),
      Cubic(-x, -k * y, -k * x, -y, 0, -y),
      Cubic(k * x, -y, x, -k * y, x, 0),
      Close,
    ]
  }
  let path : Array[@layout.PathSegment] = []
  for i, (x, y) in self.points(pen) {
    path.push(if i == 0 { Move(x, y) } else { Line(x, y) })
  }
  if self.kind != "arrow" && !path.is_empty() {
    path.push(Close)
  }
  path
}

///|
fn Object::draw_line_ends(
  self : Object,
  geometry : Geometry,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let result : Array[@layout.PositionedPrimitive] = []
  if !line_shape(self.preset) || self.stroke.is_empty() {
    return result
  }
  for (head, end) in [(true, self.ends.0), (false, self.ends.1)] {
    if end.kind != "none" &&
      self.line_end_matrix(geometry, head) is Some(matrix) {
      result.append([
        Transform(matrix),
        Path(
          end.path(self.line_width),
          if end.kind == "arrow" {
            ""
          } else {
            self.stroke
          },
          self.stroke,
          self.line_width,
          {
            fillAlpha: self.stroke_alpha,
            strokeAlpha: self.stroke_alpha,
            dash: [],
            cap: line_cap_code(self.cap),
            join: if self.join == "round" {
              1
            } else if self.join == "bevel" {
              2
            } else {
              0
            },
            miter: self.miter,
          },
        ),
        Restore,
      ])
    }
  }
  result
}

///|
fn Object::line_end_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool raise @failure.Failure {
  if self.stroke.is_empty() {
    return false
  }
  for (head, end) in [(true, self.ends.0), (false, self.ends.1)] {
    if end.kind == "none" {
      continue
    }
    guard self.line_end_matrix(geometry, head) is Some(matrix) else { continue }
    let (x, y) = matrix.inverse().point(x, y)
    if end.kind == "oval" {
      let (length, width) = end.size(self.line_width)
      let a = length / 2 + margin
      let b = width / 2 + margin
      if x * x / (a * a) + y * y / (b * b) <= 1 {
        return true
      }
    } else {
      let points = end.points(self.line_width)
      let mut inside = false
      for
        i in 0..<(if end.kind == "arrow" {
          points.length() - 1
        } else {
          points.length()
        }) {
        let (ax, ay) = points[i]
        let (bx, by) = points[(i + 1) % points.length()]
        if (ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax {
          inside = !inside
        }
        let dx = bx - ax
        let dy = by - ay
        let square = dx * dx + dy * dy
        let t = (if square > 0 {
            ((x - ax) * dx + (y - ay) * dy) / square
          } else {
            0.0
          })
          .max(0)
          .min(1)
        let gx = x - ax - t * dx
        let gy = y - ay - t * dy
        if gx * gx + gy * gy <= margin * margin {
          return true
        }
      }
      if end.kind != "arrow" && inside {
        return true
      }
    }
  }
  false
}
