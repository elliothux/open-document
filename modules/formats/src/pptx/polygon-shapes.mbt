///|
fn polygon_shape(preset : String) -> Bool {
  ["triangle", "rtTriangle", "diamond", "parallelogram", "trapezoid"].contains(
    preset,
  )
}

///|
fn polygon_adjustment_max(preset : String, w : Double, h : Double) -> Double {
  if preset == "triangle" {
    return 1
  }
  if w <= 0 || h <= 0 {
    return 0
  }
  w / w.min(h) * (if preset == "trapezoid" { 0.5 } else { 1.0 })
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
    _ => (0.0, 0.0, 0.0, 0.0)
  }
}
