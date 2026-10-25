///|
fn elbow_arrow_shape(preset : String) -> Bool {
  ["leftUpArrow", "bentUpArrow"].contains(preset)
}

///|
fn elbow_arrow_adjustments(
  preset : String,
  values : (Double, Double, Double),
) -> (Double, Double, Double) {
  let width = values.1.clamp(min=0, max=0.5)
  let bent = preset == "bentUpArrow"
  (
    values.0.clamp(min=0, max=if bent { 0.5 } else { 2 * width }),
    width,
    values.2.clamp(
      min=0,
      max=if bent { 0.5 } else { ((1.0 - 2 * width) * 100000).round() / 100000 },
    ),
  )
}

///|
fn elbow_arrow_points(
  preset : String,
  w : Double,
  h : Double,
  values : (Double, Double, Double),
) -> Array[(Double, Double)] {
  let (shaft, head, length) = elbow_arrow_adjustments(preset, values)
  let side = w.min(h)
  let tip = side * length
  let center = w - side * head
  let left = center - side * shaft / 2
  let right = center + side * shaft / 2
  let shoulder = w - 2 * side * head
  if preset == "bentUpArrow" {
    let top = h - side * shaft
    return [
      (0.0, top),
      (left, top),
      (left, tip),
      (shoulder, tip),
      (center, 0.0),
      (w, tip),
      (right, tip),
      (right, h),
      (0.0, h),
    ]
  }
  let y = h - side * head
  let top = y - side * shaft / 2
  let bottom = y + side * shaft / 2
  [
    (0.0, y),
    (tip, h - 2 * side * head),
    (tip, top),
    (left, top),
    (left, tip),
    (shoulder, tip),
    (center, 0.0),
    (w, tip),
    (right, tip),
    (right, bottom),
    (tip, bottom),
    (tip, h),
  ]
}

///|
fn elbow_arrow_insets(
  preset : String,
  w : Double,
  h : Double,
  values : (Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let (shaft, head, length) = elbow_arrow_adjustments(preset, values)
  let side = w.min(h)
  if preset == "bentUpArrow" {
    (0.0, h - side * shaft, side * (head - shaft / 2), 0.0)
  } else {
    let inset = if head > 0 { side * shaft * length / (2 * head) } else { 0.0 }
    (
      inset,
      h - side * (head + shaft / 2),
      side * head,
      side * (head - shaft / 2),
    )
  }
}

///|
fn Object::elbow_connection_sites(self : Object) -> Array[(Double, Double)] {
  let g = self.geometry.unwrap()
  let w = g.width
  let h = g.height
  let side = w.min(h)
  let (shaft, head, length) = elbow_arrow_adjustments(
    self.preset,
    self.adjustments,
  )
  let tip = side * length
  let center = w - side * head
  let right = center + side * shaft / 2
  let shoulder = w - 2 * side * head
  if self.preset == "bentUpArrow" {
    [
      (center, 0.0),
      (shoulder, tip),
      (0.0, h - side * shaft / 2),
      (right / 2, h),
      (right, (tip + h) / 2),
      (w, tip),
    ]
  } else {
    let y = h - side * head
    let bottom = y + side * shaft / 2
    [
      (center, 0.0),
      (shoulder, tip),
      (tip, h - 2 * side * head),
      (0.0, y),
      (tip, h),
      ((tip + right) / 2, bottom),
      (right, (tip + bottom) / 2),
      (w, tip),
    ]
  }
}
