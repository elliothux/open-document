///|
fn polygon_shape(preset : String) -> Bool {
  [
    "triangle", "rtTriangle", "diamond", "parallelogram", "trapezoid", "pentagon",
    "hexagon", "octagon", "plus", "star4", "star5", "star6", "star8", "chevron",
    "homePlate", "star10", "star12", "star7", "star16", "star24", "star32", "heptagon",
    "decagon", "dodecagon",
  ].contains(preset)
}

///|
fn polygon_adjustment_max(preset : String, w : Double, h : Double) -> Double {
  if preset == "triangle" {
    return 1
  }
  if [
      "octagon", "plus", "star4", "star5", "star6", "star7", "star8", "star10", "star12",
      "star16", "star24", "star32",
    ].contains(preset) {
    return 0.5
  }
  if w <= 0 || h <= 0 {
    return 0
  }
  w /
  w.min(h) *
  (if ["trapezoid", "hexagon"].contains(preset) { 0.5 } else { 1.0 })
}

///|
fn pentagon_points(w : Double, h : Double) -> Array[(Double, Double)] {
  let dx1 = w / 2 * 1.05146 * @math.cos(@math.PI / 10)
  let dx2 = w / 2 * 1.05146 * @math.cos(@math.PI * 17 / 10)
  let center = h / 2 * 1.10557
  let y1 = center * (1 - @math.sin(@math.PI / 10))
  let y2 = center * (1 - @math.sin(@math.PI * 17 / 10))
  [
    (w / 2 - dx1, y1),
    (w / 2, 0),
    (w / 2 + dx1, y1),
    (w / 2 + dx2, y2),
    (w / 2 - dx2, y2),
  ]
}

///|
fn quarter_star_points(
  w : Double,
  h : Double,
  a : Double,
  outer : Array[Double],
  inner : Array[Double],
) -> Array[(Double, Double)] {
  let points = []
  let quarter = inner.length()
  // Native presets mix rounded coefficients and trigonometric guides.
  for quadrant in 0..<4 {
    for i in 0..<quarter {
      for
        (x, y, radius) in [
          (outer[i], outer[quarter - i], 0.5),
          (inner[i], inner[quarter - 1 - i], a),
        ] {
        let (x, y) = match quadrant {
          0 => (-x, -y)
          1 => (y, -x)
          2 => (x, y)
          _ => (-y, x)
        }
        points.push((w / 2 + w * radius * x, h / 2 + h * radius * y))
      }
    }
  }
  points
}

///|
fn polygon_points(
  preset : String,
  w : Double,
  h : Double,
  adjustment : Double,
) -> Array[(Double, Double)] {
  let a = adjustment.max(0).min(polygon_adjustment_max(preset, w, h))
  let inset = w.min(h) * a
  // ONLYOFFICE CreateGeometry uses shortest-side offsets for slanted quadrilaterals.
  match preset {
    "triangle" => [(0.0, h), (w * a, 0.0), (w, h)]
    "rtTriangle" => [(0.0, h), (0.0, 0.0), (w, h)]
    "diamond" => [(0.0, h / 2), (w / 2, 0.0), (w, h / 2), (w / 2, h)]
    "parallelogram" => [(0.0, h), (inset, 0.0), (w, 0.0), (w - inset, h)]
    "trapezoid" => [(0.0, h), (inset, 0.0), (w - inset, 0.0), (w, h)]
    "chevron" =>
      [
        (0.0, 0.0),
        (w - inset, 0.0),
        (w, h / 2),
        (w - inset, h),
        (0.0, h),
        (inset, h / 2),
      ]
    "homePlate" =>
      [(0.0, 0.0), (w - inset, 0.0), (w, h / 2), (w - inset, h), (0.0, h)]
    "pentagon" => pentagon_points(w, h)
    "heptagon" => {
      // The native heptagon and star7 share their outer guides.
      let points = polygon_points("star7", w, h, 0)
      [
        for i in 0..<7 => points[2 * i]
      ]
    }
    "decagon" => {
      let dx1 = w / 2 * @math.cos(@math.PI / 5)
      let dx2 = w / 2 * @math.cos(@math.PI * 2 / 5)
      let dy1 = h / 2 * 1.05146 * @math.sin(@math.PI * 2 / 5)
      let dy2 = h / 2 * 1.05146 * @math.sin(@math.PI / 5)
      [
        (0.0, h / 2),
        (w / 2 - dx1, h / 2 - dy2),
        (w / 2 - dx2, h / 2 - dy1),
        (w / 2 + dx2, h / 2 - dy1),
        (w / 2 + dx1, h / 2 - dy2),
        (w, h / 2),
        (w / 2 + dx1, h / 2 + dy2),
        (w / 2 + dx2, h / 2 + dy1),
        (w / 2 - dx2, h / 2 + dy1),
        (w / 2 - dx1, h / 2 + dy2),
      ]
    }
    "dodecagon" => {
      let x1 = w * 2894 / 21600
      let x2 = w * 7906 / 21600
      let y1 = h * 2894 / 21600
      let y2 = h * 7906 / 21600
      [
        (0.0, y2),
        (x1, y1),
        (x2, 0.0),
        (w - x2, 0.0),
        (w - x1, y1),
        (w, y2),
        (w, h - y2),
        (w - x1, h - y1),
        (w - x2, h),
        (x2, h),
        (x1, h - y1),
        (0.0, h - y2),
      ]
    }
    "hexagon" => {
      let y = h / 2 * (1 - 1.1547 * @math.sin(@math.PI / 3))
      [
        (0.0, h / 2),
        (inset, y),
        (w - inset, y),
        (w, h / 2),
        (w - inset, h - y),
        (inset, h - y),
      ]
    }
    "octagon" =>
      [
        (0.0, inset),
        (inset, 0.0),
        (w - inset, 0.0),
        (w, inset),
        (w, h - inset),
        (w - inset, h),
        (inset, h),
        (0.0, h - inset),
      ]
    "plus" =>
      [
        (0.0, inset),
        (inset, inset),
        (inset, 0.0),
        (w - inset, 0.0),
        (w - inset, inset),
        (w, inset),
        (w, h - inset),
        (w - inset, h - inset),
        (w - inset, h),
        (inset, h),
        (inset, h - inset),
        (0.0, h - inset),
      ]
    "star4" => {
      let x = w * a * @math.cos(@math.PI / 4)
      let y = h * a * @math.sin(@math.PI / 4)
      [
        (0.0, h / 2),
        (w / 2 - x, h / 2 - y),
        (w / 2, 0.0),
        (w / 2 + x, h / 2 - y),
        (w, h / 2),
        (w / 2 + x, h / 2 + y),
        (w / 2, h),
        (w / 2 - x, h / 2 + y),
      ]
    }
    "star8" => {
      let x = w / 2 * @math.cos(@math.PI / 4)
      let y = h / 2 * @math.sin(@math.PI / 4)
      let x1 = w * a * 0.92388
      let x2 = w * a * 0.38268
      let y1 = h * a * 0.92388
      let y2 = h * a * 0.38268
      [
        (0.0, h / 2),
        (w / 2 - x1, h / 2 - y2),
        (w / 2 - x, h / 2 - y),
        (w / 2 - x2, h / 2 - y1),
        (w / 2, 0.0),
        (w / 2 + x2, h / 2 - y1),
        (w / 2 + x, h / 2 - y),
        (w / 2 + x1, h / 2 - y2),
        (w, h / 2),
        (w / 2 + x1, h / 2 + y2),
        (w / 2 + x, h / 2 + y),
        (w / 2 + x2, h / 2 + y1),
        (w / 2, h),
        (w / 2 - x2, h / 2 + y1),
        (w / 2 - x, h / 2 + y),
        (w / 2 - x1, h / 2 + y2),
      ]
    }
    "star10" => {
      let dx1 = w / 2 * 1.05146 * 0.95106
      let dx2 = w / 2 * 1.05146 * 0.58779
      let dy1 = h / 2 * 0.80902
      let dy2 = h / 2 * 0.30902
      let ix = w * 1.05146 * a
      let iy = h * a
      let sx1 = ix * 0.80902
      let sx2 = ix * 0.30902
      let sy1 = iy * 0.95106
      let sy2 = iy * 0.58779
      [
        (w / 2 - dx1, h / 2 - dy2),
        (w / 2 - sx1, h / 2 - sy2),
        (w / 2 - dx2, h / 2 - dy1),
        (w / 2 - sx2, h / 2 - sy1),
        (w / 2, 0.0),
        (w / 2 + sx2, h / 2 - sy1),
        (w / 2 + dx2, h / 2 - dy1),
        (w / 2 + sx1, h / 2 - sy2),
        (w / 2 + dx1, h / 2 - dy2),
        (w / 2 + ix, h / 2),
        (w / 2 + dx1, h / 2 + dy2),
        (w / 2 + sx1, h / 2 + sy2),
        (w / 2 + dx2, h / 2 + dy1),
        (w / 2 + sx2, h / 2 + sy1),
        (w / 2, h),
        (w / 2 - sx2, h / 2 + sy1),
        (w / 2 - dx2, h / 2 + dy1),
        (w / 2 - sx1, h / 2 + sy2),
        (w / 2 - dx1, h / 2 + dy2),
        (w / 2 - ix, h / 2),
      ]
    }
    "star12" => {
      let dx = w / 2 * @math.cos(@math.PI / 6)
      let dy = h / 2 * @math.sin(@math.PI / 3)
      let x1 = w * a * @math.cos(@math.PI / 12)
      let x2 = w * a * @math.cos(@math.PI / 4)
      let x3 = w * a * @math.cos(@math.PI * 5 / 12)
      let y1 = h * a * @math.sin(@math.PI * 5 / 12)
      let y2 = h * a * @math.sin(@math.PI / 4)
      let y3 = h * a * @math.sin(@math.PI / 12)
      [
        (0.0, h / 2),
        (w / 2 - x1, h / 2 - y3),
        (w / 2 - dx, h / 4),
        (w / 2 - x2, h / 2 - y2),
        (w / 4, h / 2 - dy),
        (w / 2 - x3, h / 2 - y1),
        (w / 2, 0.0),
        (w / 2 + x3, h / 2 - y1),
        (w * 3 / 4, h / 2 - dy),
        (w / 2 + x2, h / 2 - y2),
        (w / 2 + dx, h / 4),
        (w / 2 + x1, h / 2 - y3),
        (w, h / 2),
        (w / 2 + x1, h / 2 + y3),
        (w / 2 + dx, h * 3 / 4),
        (w / 2 + x2, h / 2 + y2),
        (w * 3 / 4, h / 2 + dy),
        (w / 2 + x3, h / 2 + y1),
        (w / 2, h),
        (w / 2 - x3, h / 2 + y1),
        (w / 4, h / 2 + dy),
        (w / 2 - x2, h / 2 + y2),
        (w / 2 - dx, h * 3 / 4),
        (w / 2 - x1, h / 2 + y3),
      ]
    }
    "star16" =>
      quarter_star_points(w, h, a, [1, 0.92388, 0.70711, 0.38268, 0], [
        0.98079, 0.83147, 0.55557, 0.19509,
      ])
    "star24" =>
      quarter_star_points(
        w,
        h,
        a,
        [
          1,
          @math.cos(@math.PI / 12),
          @math.cos(@math.PI / 6),
          @math.cos(@math.PI / 4),
          0.5,
          @math.cos(@math.PI * 5 / 12),
          0,
        ],
        [0.99144, 0.92388, 0.79335, 0.60876, 0.38268, 0.13053],
      )
    "star32" =>
      quarter_star_points(
        w,
        h,
        a,
        [
          1,
          0.98079,
          0.92388,
          0.83147,
          @math.cos(@math.PI / 4),
          0.55557,
          0.38268,
          0.19509,
          0,
        ],
        [0.99518, 0.95694, 0.88192, 0.77301, 0.63439, 0.47140, 0.29028, 0.09802],
      )
    "star7" => {
      let rx = w / 2 * 1.02572
      let ry = h / 2 * 1.05210
      let ix = w * 1.02572 * a
      let iy = h * 1.05210 * a
      [
        (w / 2 - rx * 0.97493, ry * (1 + 0.22252)),
        (w / 2 - ix * 0.97493, ry - iy * 0.22252),
        (w / 2 - rx * 0.78183, ry * (1 - 0.62349)),
        (w / 2 - ix * 0.43388, ry - iy * 0.90097),
        (w / 2, 0.0),
        (w / 2 + ix * 0.43388, ry - iy * 0.90097),
        (w / 2 + rx * 0.78183, ry * (1 - 0.62349)),
        (w / 2 + ix * 0.97493, ry - iy * 0.22252),
        (w / 2 + rx * 0.97493, ry * (1 + 0.22252)),
        (w / 2 + ix * 0.78183, ry + iy * 0.62349),
        (w / 2 + rx * 0.43388, ry * (1 + 0.90097)),
        (w / 2, ry + iy),
        (w / 2 - rx * 0.43388, ry * (1 + 0.90097)),
        (w / 2 - ix * 0.78183, ry + iy * 0.62349),
      ]
    }
    "star6" => {
      let dx = w / 2 * 1.1547 * @math.cos(@math.PI / 6)
      let inner_x = w * 1.1547 * a
      let inner_y = h * a * @math.sin(@math.PI / 3)
      [
        (w / 2 - dx, h / 4),
        (w / 2 - inner_x / 2, h / 2 - inner_y),
        (w / 2, 0.0),
        (w / 2 + inner_x / 2, h / 2 - inner_y),
        (w / 2 + dx, h / 4),
        (w / 2 + inner_x, h / 2),
        (w / 2 + dx, h * 3 / 4),
        (w / 2 + inner_x / 2, h / 2 + inner_y),
        (w / 2, h),
        (w / 2 - inner_x / 2, h / 2 + inner_y),
        (w / 2 - dx, h * 3 / 4),
        (w / 2 - inner_x, h / 2),
      ]
    }
    "star5" => {
      let outer = pentagon_points(w, h)
      let rx = w * 1.05146 * a
      let ry = h * 1.10557 * a
      let x1 = rx * @math.cos(@math.PI / 10)
      let x2 = rx * @math.cos(@math.PI * 3 / 10)
      let center = h / 2 * 1.10557
      let y1 = center - ry * @math.sin(@math.PI * 3 / 10)
      let y2 = center + ry * @math.sin(@math.PI / 10)
      [
        outer[0],
        (w / 2 - x2, y1),
        outer[1],
        (w / 2 + x2, y1),
        outer[2],
        (w / 2 + x1, y2),
        outer[3],
        (w / 2, center + ry),
        outer[4],
        (w / 2 - x1, y2),
      ]
    }
    _ => []
  }
}

///|
fn polygon_insets(
  preset : String,
  w : Double,
  h : Double,
  adjustment : Double,
) -> (Double, Double, Double, Double) {
  let maximum = polygon_adjustment_max(preset, w, h)
  let a = adjustment.max(0).min(maximum)
  match preset {
    "triangle" => (w * a / 2, h / 2, w * (1 - a) / 2, 0.0)
    "rtTriangle" => (w / 12, h * 7 / 12, w * 5 / 12, h / 12)
    "diamond" => (w / 4, h / 4, w / 4, h / 4)
    "parallelogram" => {
      let q = (1.0 + 5 * (if maximum > 0 { a / maximum } else { 0.0 })) / 12
      (q * w, q * h, q * w, q * h)
    }
    "trapezoid" => {
      let q = (if maximum > 0 { a / maximum } else { 0.0 }) / 3
      (q * w, q * h, q * w, 0.0)
    }
    "chevron" => {
      let inset = w.min(h) * a
      if inset * 2 < w {
        (inset, 0.0, inset, 0.0)
      } else {
        (0.0, 0.0, 0.0, 0.0)
      }
    }
    "homePlate" => (0.0, 0.0, w.min(h) * a / 2, 0.0)
    "heptagon" | "decagon" | "dodecagon" => {
      let (x, y) = polygon_points(preset, w, h, a)[1]
      (x, y, x, y)
    }
    "pentagon" => {
      let points = pentagon_points(w, h)
      let top = if w > 0 {
        points[0].1 * (points[3].0 - w / 2) / (w / 2 - points[0].0)
      } else {
        0.0
      }
      (points[4].0, top, w - points[3].0, h - points[3].1)
    }
    "hexagon" => {
      let ratio = if maximum > 0 { a / maximum } else { 0.0 }
      let q : Double = (if ratio > 0.5 { 1 + 6 * ratio } else { 2 + 4 * ratio }) /
        24
      (w * q, h * q, w * q, h * q)
    }
    "octagon" => {
      let cut = w.min(h) * a / 2
      (cut, cut, cut, cut)
    }
    "plus" => {
      let cut = w.min(h) * a
      if w > h {
        (0.0, cut, 0.0, cut)
      } else {
        (cut, 0.0, cut, 0.0)
      }
    }
    "star4" | "star8" | "star12" | "star16" | "star24" | "star32" => {
      let factor = if preset == "star8" {
        0.92388
      } else {
        @math.cos(@math.PI / 4)
      }
      let x = w / 2 - w * a * factor
      let y = h / 2 - h * a * factor
      (x, y, x, y)
    }
    "star6" => {
      let x = w / 2 - w * 1.1547 * a
      let y = h / 2 - h * a * @math.sin(@math.PI / 3)
      (x, y, x, y)
    }
    "star10" => {
      let x = w / 2 - w * 1.05146 * a * 0.80902
      let y = h / 2 - h * a * 0.58779
      (x, y, x, y)
    }
    "star5" => {
      let points = polygon_points(preset, w, h, a)
      (points[9].0, points[1].1, w - points[5].0, h - points[7].1)
    }
    "star7" => {
      let points = polygon_points(preset, w, h, a)
      (points[13].0, points[3].1, w - points[9].0, h - points[9].1)
    }
    _ => (0.0, 0.0, 0.0, 0.0)
  }
}
