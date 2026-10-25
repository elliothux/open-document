///|
fn rounded_shape(preset : String) -> Bool {
  [
    "roundRect", "round1Rect", "round2SameRect", "round2DiagRect", "snipRoundRect",
  ].contains(preset)
}

///|
fn rounded_corners(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let side = width.min(height)
  let first = side * adjustments.0.clamp(min=0, max=0.5)
  let second = side * adjustments.1.clamp(min=0, max=0.5)
  match preset {
    "round1Rect" => (0.0, first, 0.0, 0.0)
    "round2SameRect" => (first, first, second, second)
    "round2DiagRect" => (first, second, first, second)
    "snipRoundRect" => (first, 0.0, 0.0, 0.0)
    _ => (first, first, first, first)
  }
}

///|
fn rounded_path(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> Array[@layout.PathSegment] {
  let (tl, tr, br, bl) = rounded_corners(preset, width, height, adjustments)
  let tr = if preset == "snipRoundRect" {
    width.min(height) * adjustments.1.clamp(min=0, max=0.5)
  } else {
    tr
  }
  let k = 0.5522847498307936
  [
    Move(tl, 0),
    Line(width - tr, 0),
    if preset == "snipRoundRect" {
      Line(width, tr)
    } else {
      Cubic(width - tr + k * tr, 0, width, tr - k * tr, width, tr)
    },
    Line(width, height - br),
    Cubic(
      width,
      height - br + k * br,
      width - br + k * br,
      height,
      width - br,
      height,
    ),
    Line(bl, height),
    Cubic(bl - k * bl, height, 0, height - bl + k * bl, 0, height - bl),
    Line(0, tl),
    Cubic(0, tl - k * tl, tl - k * tl, 0, tl, 0),
    Close,
  ]
}

///|
fn rounded_insets(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let side = width.min(height)
  let first = side * adjustments.0.clamp(min=0, max=0.5) * 0.29289
  let second = side * adjustments.1.clamp(min=0, max=0.5) * 0.29289
  match preset {
    "round1Rect" => (0.0, 0.0, first, 0.0)
    "round2SameRect" => (first.max(second), first, first.max(second), second)
    "round2DiagRect" => {
      let inset = first.max(second)
      (inset, inset, inset, inset)
    }
    "snipRoundRect" =>
      (first, first, side * adjustments.1.clamp(min=0, max=0.5) / 2, 0.0)
    _ => (first, first, first, first)
  }
}

///|
fn Object::rounded_hit(
  self : Object,
  width : Double,
  height : Double,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  let (tl, tr, br, bl) = rounded_corners(
    self.preset,
    width,
    height,
    self.adjustments,
  )
  let radius = if y < height / 2 {
    if x < width / 2 {
      tl
    } else {
      tr
    }
  } else if x < width / 2 {
    bl
  } else {
    br
  }
  let qx = (x - width / 2).abs() - (width / 2 - radius)
  let qy = (y - height / 2).abs() - (height / 2 - radius)
  let mut distance = (qx.max(0) * qx.max(0) + qy.max(0) * qy.max(0)).sqrt() +
    qx.max(qy).min(0) -
    radius
  if self.preset == "snipRoundRect" {
    let cut = width.min(height) * self.adjustments.1.clamp(min=0, max=0.5)
    if cut > 0 && x >= width - cut && y <= cut {
      let t = ((x - width + cut + y) / (2 * cut)).clamp(min=0, max=1)
      let dx = x - width + cut - t * cut
      let dy = y - t * cut
      distance = (dx * dx + dy * dy).sqrt() *
        (if x - y > width - cut { 1.0 } else { -1.0 })
    }
  }
  (self.has_fill() && distance <= 0) ||
  (!self.stroke.is_empty() && distance.abs() <= margin)
}
