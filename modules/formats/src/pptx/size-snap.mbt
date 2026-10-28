///|
fn size_snap_frame(object : Object) -> Geometry? {
  guard object.parent.is_empty() &&
    object.kind != "image" &&
    object.source.node.name != "cxnSp" &&
    !line_shape(object.preset) &&
    object.geometry is Some(g) &&
    g.rotation == 0 &&
    g.matrix.b.abs() < 1.0e-12 &&
    g.matrix.c.abs() < 1.0e-12 &&
    g.matrix.a.abs() > 1.0e-12 &&
    g.matrix.d.abs() > 1.0e-12 else {
    return None
  }
  Some(g)
}

///|
fn size_snap_targets(slide : Slide, active : String) -> Array[Object] {
  slide.objects.filter(object => {
    object.id != active &&
    object.parent.is_empty() &&
    object.source.tree.part == slide.tree.part &&
    object.geometry.map(g => g.width >= 0.1 && g.height >= 0.1).unwrap_or(false)
  })
}

///|
fn nearest_snap_size(
  values : Array[Double],
  value : Double,
  tolerance : Double,
) -> Double? {
  guard value > 0 else { return None }
  let mut best : Double? = None
  for size in values {
    let distance = (size - value).abs()
    if distance <= tolerance &&
      best.map(previous => distance < (previous - value).abs()).unwrap_or(true) {
      best = Some(size)
    }
  }
  best
}

///|
fn Session::snap_resize_size(
  self : Session,
  slide : Slide,
  dx : Double,
  dy : Double,
  handle : Int32,
  tolerance : Double,
  center : Bool,
) -> (Double, Double, (Bool, Bool)) raise @failure.Failure {
  guard self.selection.objects.length() == 1 &&
    size_snap_frame(slide.object(self.selection.object)) is Some(g) else {
    return (dx, dy, (false, false))
  }
  let targets = size_snap_targets(slide, self.selection.object)
  let left = handle == 1 || handle == 4
  let top = handle == 1 || handle == 2
  let factor = if center { 2.0 } else { 1.0 }
  let raw_width = g.width + (if left { -dx } else { dx }) * factor / g.matrix.a
  let raw_height = g.height + (if top { -dy } else { dy }) * factor / g.matrix.d
  let width = if dx == 0 || raw_width == 0 {
    None
  } else {
    nearest_snap_size(
      targets.map(object => object.geometry.unwrap().width),
      raw_width.abs(),
      tolerance * factor / g.matrix.a.abs(),
    ).map(value => if raw_width < 0 { -value } else { value })
  }
  let height = if dy == 0 || raw_height == 0 {
    None
  } else {
    nearest_snap_size(
      targets.map(object => object.geometry.unwrap().height),
      raw_height.abs(),
      tolerance * factor / g.matrix.d.abs(),
    ).map(value => if raw_height < 0 { -value } else { value })
  }
  (
    width
    .map(width => {
      (width - g.width) * (if left { -g.matrix.a } else { g.matrix.a }) / factor
    })
    .unwrap_or(dx),
    height
    .map(height => {
      (height - g.height) *
      (if top { -g.matrix.d } else { g.matrix.d }) /
      factor
    })
    .unwrap_or(dy),
    (width is Some(_), height is Some(_)),
  )
}

///|
fn Session::snap_size(self : Session) -> Array[Json] raise @failure.Failure {
  guard self.candidate is Some(candidate) &&
    (candidate.snap_size.0 || candidate.snap_size.1) else {
    return []
  }
  let slide = self.current()
  guard size_snap_frame(slide.object(self.selection.object)) is Some(g) else {
    return []
  }
  let marks : Array[Json] = []
  for object in size_snap_targets(slide, self.selection.object) {
    let target = object.geometry.unwrap()
    // Quantization and minimum sizes must still leave the actual dimensions equal.
    let width = candidate.snap_size.0 &&
      ((target.width - g.width) * g.matrix.a).abs() <= 1.0 / 12700
    let height = candidate.snap_size.1 &&
      ((target.height - g.height) * g.matrix.d).abs() <= 1.0 / 12700
    if width || height {
      marks.push({
        "object": object.id,
        "width": width,
        "height": height,
        "outline": polygon(target.matrix, 0, 0, target.width, target.height),
      })
      if marks.length() == 64 {
        break
      }
    }
  }
  marks
}
