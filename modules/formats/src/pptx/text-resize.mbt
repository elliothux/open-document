///|
fn frame_extent(
  object : Object,
  geometry : Geometry,
  required : Double,
  horizontal~ : Bool,
) -> Double raise @failure.Failure {
  let usable = fn(value : Double) {
    let trial = object.text_extent(geometry, value, horizontal~)
    let (body, _, _) = object.text_plane(trial)
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
  guard object.read_only.is_empty() ||
    object.read_only == "Group members are read-only" else {
    @failure.reject("protected-content", "Automatic shape resizing is locked")
  }
  for parent = object.source.node.parent
      parent >= 0
      parent = object.source.tree.nodes[parent].parent {
    let node = object.source.tree.nodes[parent]
    if node.name == "grpSp" && node.uri == presentation_uri {
      let group : Ref = { tree: object.source.tree, node, }
      let locks = group
        .child("nvGrpSpPr", uri=presentation_uri)
        .bind(nv => nv.child("cNvGrpSpPr", uri=presentation_uri))
        .bind(properties => properties.child("grpSpLocks"))
      guard !(locks is Some(locks) &&
        (flag(locks.node, "noMove") || flag(locks.node, "noResize"))) else {
        @failure.reject(
          "protected-content", "Automatic shape resizing is locked",
        )
      }
    }
  }
  let original = object.geometry.unwrap()
  let mut geometry = if object.body.columns > 1 {
    original
  } else {
    object.text_extent(original, 14400, horizontal=false)
  }
  let unwrapped = if object.body.wrap {
    None
  } else {
    let trial = object.text_extent(geometry, 14400, horizontal=true)
    let (body, frame, _) = object.text_plane(trial)
    let measured = measure_text(
      {
        ..object,
        body,
        paragraphs: object.paragraphs.map(p => { ..p, align: "left", }),
      },
      frame,
      probe,
      profile,
      1,
    )
    let width = measured.0.fold(init=1.0 / 12700, (width, line) => {
      width.max(
        line.x -
        line.areaX +
        line.width +
        object.paragraphs[line.paragraph].right,
      )
    })
    Some(
      (
        width * body.columns.to_double() +
        (body.columns - 1).to_double() * body.columnGap,
        measured.1 - body.top - body.bottom,
      ),
    )
  }
  for _ in 0..<16 {
    let (body, frame, _) = object.text_plane(geometry)
    let (width, height) = if unwrapped is Some(size) {
      size
    } else {
      let measured = measure_text({ ..object, body, }, frame, probe, profile, 1)
      (
        frame.width - body.left - body.right,
        measured.1 - body.top - body.bottom,
      )
    }
    let next = if unwrapped is Some(_) {
      object.text_extent(
        geometry,
        frame_extent(object, geometry, width, horizontal=true),
        horizontal=true,
      )
    } else {
      geometry
    }
    let next = object.text_extent(
      next,
      frame_extent(object, next, height.max(1.0 / 12700), horizontal=false),
      horizontal=false,
    )
    if (next.width - geometry.width).abs() < 0.5 / 12700 &&
      (next.height - geometry.height).abs() < 0.5 / 12700 {
      // ONLYOFFICE keeps a rotated frame's center; otherwise text alignment anchors it.
      let rotated = original.rotation != 0
      let dx = original.width - next.width
      let dy = original.height - next.height
      let align = match object.paragraphs[0].align {
        "center" => 0.5
        "right" => 1.0
        _ => 0.0
      }
      let anchor = match object.body.anchor {
        "ctr" => 0.5
        "b" => 1.0
        _ => 0.0
      }
      let (horizontal, vertical) = match object.body.direction {
        "vert" => (1.0 - anchor, align)
        "vert270" => (anchor, 1.0 - align)
        _ => (align, anchor)
      }
      let x = original.x + dx * (if rotated { 0.5 } else { horizontal })
      let y = original.y + dy * (if rotated { 0.5 } else { vertical })
      validate_object_box(x, y, next.width, next.height, false)
      let (_, _, diagnostic, _) = fit_text(object, next, probe, profile)
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
