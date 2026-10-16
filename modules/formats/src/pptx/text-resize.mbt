///|
fn frame_extent(
  object : Object,
  geometry : Geometry,
  required : Double,
  horizontal~ : Bool,
) -> Double raise @failure.Failure {
  let usable = fn(value : Double) {
    let trial = if horizontal {
      { ..geometry, width: value, }
    } else {
      { ..geometry, height: value, }
    }
    let body = object.shape_body(trial)
    if horizontal {
      value - body.left - body.right
    } else {
      value - body.top - body.bottom
    }
  }
  guard usable(14400) >= required else {
    @failure.reject("layout-overflow", "Text exceeds the maximum shape size")
  }
  let mut low = 0.0
  let mut high = 14400.0
  // Invert the existing preset text rectangle without repeating font shaping.
  for _ in 0..<32 {
    let mid = (low + high) / 2
    if usable(mid) >= required {
      high = mid
    } else {
      low = mid
    }
  }
  ((high * 12700).ceil() / 12700).max(0.1)
}

///|
fn resize_text_frame(
  object : Object,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Geometry raise @failure.Failure {
  guard object.read_only.is_empty() && object.parent.is_empty() else {
    @failure.reject("protected-content", "Automatic shape resizing is locked")
  }
  let original = object.geometry.unwrap()
  let mut geometry = { ..original, height: 14400, }
  let unwrapped = if object.body.wrap {
    None
  } else {
    let trial = { ..geometry, width: 14400, }
    let body = object.shape_body(trial)
    let measured = measure_text(
      {
        ..object,
        body,
        paragraphs: object.paragraphs.map(p => { ..p, align: "left", }),
      },
      trial,
      probe,
      profile,
      1,
    )
    let width = measured.0.fold(init=1.0 / 12700, (width, line) => {
      width.max(
        line.x -
        body.left +
        line.width +
        object.paragraphs[line.paragraph].right,
      )
    })
    Some((width, measured.1 - body.top - body.bottom))
  }
  for _ in 0..<16 {
    let body = object.shape_body(geometry)
    let (width, height) = if unwrapped is Some(size) {
      size
    } else {
      let measured = measure_text(
        { ..object, body, },
        geometry,
        probe,
        profile,
        1,
      )
      (
        geometry.width - body.left - body.right,
        measured.1 - body.top - body.bottom,
      )
    }
    let next = if unwrapped is Some(_) {
      {
        ..geometry,
        width: frame_extent(object, geometry, width, horizontal=true),
      }
    } else {
      geometry
    }
    let next = {
      ..next,
      height: frame_extent(
        object,
        next,
        height.max(1.0 / 12700),
        horizontal=false,
      ),
    }
    if (next.width - geometry.width).abs() < 0.5 / 12700 &&
      (next.height - geometry.height).abs() < 0.5 / 12700 {
      // ONLYOFFICE keeps a rotated frame's center; otherwise text alignment anchors it.
      let rotated = original.rotation != 0
      let dx = original.width - next.width
      let dy = original.height - next.height
      let x = original.x +
        (if rotated || object.paragraphs[0].align == "center" {
          dx / 2
        } else if object.paragraphs[0].align == "right" {
          dx
        } else {
          0
        })
      let y = original.y +
        (if rotated || object.body.anchor == "ctr" {
          dy / 2
        } else if object.body.anchor == "b" {
          dy
        } else {
          0
        })
      validate_object_box(x, y, next.width, next.height, false)
      let (_, _, diagnostic) = fit_text(object, next, probe, profile)
      guard diagnostic.is_empty() else {
        @failure.reject("layout-overflow", diagnostic)
      }
      return { ..next, x, y, }
    }
    geometry = next
  }
  @failure.reject("layout-overflow", "Automatic shape size did not converge")
}

///|
fn resized_frame_changes(
  object : Object,
  target : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let original = object.geometry.unwrap()
  if original.x == target.x &&
    original.y == target.y &&
    original.width == target.width &&
    original.height == target.height {
    []
  } else {
    transform_changes(object, target)
  }
}
