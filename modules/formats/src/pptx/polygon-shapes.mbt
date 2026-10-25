///|
fn polygon_shape(preset : String) -> Bool {
  [
    "triangle", "rtTriangle", "diamond", "parallelogram", "trapezoid", "pentagon",
    "hexagon", "octagon", "plus", "star4", "star5", "star6", "star8", "chevron",
    "homePlate",
  ].contains(preset)
}

///|
fn polygon_adjustment_max(preset : String, w : Double, h : Double) -> Double {
  if preset == "triangle" {
    return 1
  }
  if ["octagon", "plus", "star4", "star5", "star6", "star8"].contains(preset) {
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
    "star4" | "star8" => {
      let factor = if preset == "star4" {
        @math.cos(@math.PI / 4)
      } else {
        0.92388
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
    "star5" => {
      let points = polygon_points(preset, w, h, a)
      (points[9].0, points[1].1, w - points[5].0, h - points[7].1)
    }
    _ => (0.0, 0.0, 0.0, 0.0)
  }
}
