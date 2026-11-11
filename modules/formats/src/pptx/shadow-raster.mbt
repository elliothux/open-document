///|
fn shadow_bounds(
  path : Array[@layout.PathSegment],
  blur : Double,
) -> @layout.Border raise @failure.Failure {
  guard !path.is_empty() &&
    path.length() <= 4096 &&
    !blur.is_nan() &&
    blur >= 0 &&
    blur <= 128 else {
    @failure.reject(
      "limit-exceeded", "Outer shadow path or blur exceeds budget",
    )
  }
  let mut left = 1.0e9
  let mut top = 1.0e9
  let mut right = -1.0e9
  let mut bottom = -1.0e9
  for segment in path {
    let points = match segment {
      @layout.Move(x, y) | @layout.Line(x, y) => [(x, y)]
      @layout.Cubic(a, b, c, d, x, y) => [(a, b), (c, d), (x, y)]
      @layout.Close => []
    }
    for (x, y) in points {
      guard !x.is_nan() && !y.is_nan() && x.abs() <= 57600 && y.abs() <= 57600 else {
        @failure.reject(
          "limit-exceeded", "Outer shadow coordinates exceed budget",
        )
      }
      left = left.min(x)
      top = top.min(y)
      right = right.max(x)
      bottom = bottom.max(y)
    }
  }
  let padding = (blur * 2).ceil() + 1
  let x = (left * 2).floor() - padding
  let y = (top * 2).floor() - padding
  let width = (right * 2).ceil() + padding - x
  let height = (bottom * 2).ceil() + padding - y
  guard width > 0 &&
    width <= @layout.ImageDimension.to_double() &&
    height > 0 &&
    height <= @layout.ImageDimension.to_double() &&
    width * height <= (@layout.ImageBytes / 4).to_double() else {
    @failure.reject(
      "limit-exceeded", "Outer shadow bitmap exceeds image budget",
    )
  }
  { x: x / 2, y: y / 2, width: width / 2, height: height / 2, }
}

///|
fn shadow_edge(
  edges : Array[(Double, Double, Double, Double)],
  x : Double,
  y : Double,
  next_x : Double,
  next_y : Double,
) -> Unit raise @failure.Failure {
  guard edges.length() < 32768 else {
    @failure.reject("limit-exceeded", "Outer shadow contour exceeds budget")
  }
  if y != next_y {
    edges.push((x, y, next_x, next_y))
  }
}

///|
fn shadow_curve(
  edges : Array[(Double, Double, Double, Double)],
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  x3 : Double,
  y3 : Double,
  depth : Int32,
) -> Unit raise @failure.Failure {
  let dx = x3 - x0
  let dy = y3 - y0
  let chord = dx * dx + dy * dy
  let error = ((x1 - x3) * dy - (y1 - y3) * dx).abs() +
    ((x2 - x3) * dy - (y2 - y3) * dx).abs()
  if (chord > 0 && error * error <= 0.0009765625 * chord) ||
    (
      chord == 0 &&
      (x1 - x0)
      .abs()
      .max((y1 - y0).abs())
      .max((x2 - x0).abs())
      .max((y2 - y0).abs()) <=
      0.03125
    ) {
    shadow_edge(edges, x0, y0, x3, y3)
    return
  }
  guard depth < 12 else {
    @failure.reject(
      "limit-exceeded", "Outer shadow curve exceeds subdivision budget",
    )
  }
  let ax = (x0 + x1) / 2
  let ay = (y0 + y1) / 2
  let bx = (x1 + x2) / 2
  let by = (y1 + y2) / 2
  let cx = (x2 + x3) / 2
  let cy = (y2 + y3) / 2
  let dx = (ax + bx) / 2
  let dy = (ay + by) / 2
  let ex = (bx + cx) / 2
  let ey = (by + cy) / 2
  let mx = (dx + ex) / 2
  let my = (dy + ey) / 2
  shadow_curve(edges, x0, y0, ax, ay, dx, dy, mx, my, depth + 1)
  shadow_curve(edges, mx, my, ex, ey, cx, cy, x3, y3, depth + 1)
}

///|
fn shadow_edges(
  path : Array[@layout.PathSegment],
) -> Array[(Double, Double, Double, Double)] raise @failure.Failure {
  let edges = []
  let mut pen = (0.0, 0.0)
  let mut start = (0.0, 0.0)
  let mut open = false
  for segment in path {
    match segment {
      @layout.Move(x, y) => {
        if open {
          shadow_edge(edges, pen.0, pen.1, start.0, start.1)
        }
        pen = (x, y)
        start = pen
        open = true
      }
      @layout.Line(x, y) => {
        shadow_edge(edges, pen.0, pen.1, x, y)
        pen = (x, y)
      }
      @layout.Cubic(a, b, c, d, x, y) => {
        shadow_curve(edges, pen.0, pen.1, a, b, c, d, x, y, 0)
        pen = (x, y)
      }
      @layout.Close => {
        shadow_edge(edges, pen.0, pen.1, start.0, start.1)
        pen = start
        open = false
      }
    }
  }
  if open {
    shadow_edge(edges, pen.0, pen.1, start.0, start.1)
  }
  edges
}

///|
fn shadow_coverage(
  path : Array[@layout.PathSegment],
  bounds : @layout.Border,
) -> Array[Double] raise @failure.Failure {
  let width = (bounds.width * 2).to_int()
  let height = (bounds.height * 2).to_int()
  let edges = shadow_edges(path)
  guard edges.length().to_int64() * height.to_int64() * 8 <= 16777216 else {
    @failure.reject("limit-exceeded", "Outer shadow scan exceeds work budget")
  }
  let pixels = Array::make(width * height, 0.0)
  for row in 0..<height {
    for sample in 0..<8 {
      let y = bounds.y + (row.to_double() + (sample.to_double() + 0.5) / 8) / 2
      let hits : Array[(Double, Int32)] = []
      for (x1, y1, x2, y2) in edges {
        if y >= y1.min(y2) && y < y1.max(y2) {
          hits.push(
            (
              (x1 + (y - y1) * (x2 - x1) / (y2 - y1) - bounds.x) * 2,
              if y2 > y1 {
                1
              } else {
                -1
              },
            ),
          )
        }
      }
      hits.sort_by((a, b) => a.0.compare(b.0))
      let mut winding = 0
      let mut previous = 0.0
      for (x, delta) in hits {
        if winding != 0 {
          let left = previous.max(0).min(width.to_double())
          let right = x.max(0).min(width.to_double())
          if right > left {
            for column in left.floor().to_int()..<right.ceil().to_int() {
              pixels[row * width + column] += (
                  right.min(column.to_double() + 1) -
                  left.max(column.to_double())
                ) *
                255 /
                8
            }
          }
        }
        previous = x
        winding += delta
      }
    }
  }
  pixels
}

///|
fn shadow_blur_axis(
  input : Array[Double],
  width : Int32,
  height : Int32,
  radius : Int32,
  vertical : Bool,
) -> Array[Double] raise @failure.Failure {
  let output = Array::make(input.length(), 0.0)
  let length = if vertical { height } else { width }
  let lines = if vertical { width } else { height }
  let denominator = ((radius + 1) * (radius + 1)).to_double()
  let mut work = 0
  for line in 0..<lines {
    let changes = Array::make(length, 0.0)
    let mut previous = 0.0
    for position in 0..<length {
      let index = if vertical {
        position * width + line
      } else {
        line * width + position
      }
      let value = input[index]
      let delta = value - previous
      previous = value
      if delta.abs() > 1.0e-8 {
        work += radius * 2 + 1
        guard work <= 33554432 else {
          @failure.reject(
            "limit-exceeded", "Outer shadow blur exceeds work budget",
          )
        }
        for
          offset in (-radius).max(-position)..<(radius.min(
            length - position - 1,
          ) +
          1) {
          changes[position + offset] += delta *
            (radius + 1 - offset.abs()).to_double() /
            denominator
        }
      }
    }
    let mut value = 0.0
    for position in 0..<length {
      value += changes[position]
      let index = if vertical {
        position * width + line
      } else {
        line * width + position
      }
      output[index] = value.max(0).min(255)
    }
  }
  output
}

///|
fn shadow_pixels(
  image : ShadowImage,
  shadow : OuterShadow,
) -> Bytes raise @failure.Failure {
  let width = (image.bounds.width * 2).to_int()
  let height = (image.bounds.height * 2).to_int()
  let coverage = shadow_coverage(image.path, image.bounds)
  // Stack blur is a separable triangular kernel; sparse changes avoid filtering constant spans repeatedly.
  let radius = (shadow.blur * 2).ceil().to_int()
  let pixels = if radius == 0 {
    coverage
  } else {
    shadow_blur_axis(
      shadow_blur_axis(coverage, width, height, radius, false),
      width,
      height,
      radius,
      true,
    )
  }
  let rgb = [0, 2, 4].map(i => {
    (@string.parse_int(shadow.color[i:i + 2], base=16) catch {
      _ => @failure.reject("unsupported-style", "Invalid outer shadow color")
    }).to_byte()
  })
  Bytes::makei(width * height * 4, index => {
    let alpha = (pixels[index / 4] * image.alpha)
      .round()
      .to_int()
      .max(0)
      .min(255)
      .to_byte()
    if index % 4 == 3 {
      alpha
    } else if alpha == 0 {
      b'\x00'
    } else {
      rgb[index % 4]
    }
  })
}
