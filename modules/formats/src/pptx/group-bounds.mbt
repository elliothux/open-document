///|
fn member_geometry_changed(before : Geometry, after : Geometry) -> Bool {
  before.x != after.x ||
  before.y != after.y ||
  before.width != after.width ||
  before.height != after.height ||
  before.rotation != after.rotation ||
  before.flip_x != after.flip_x ||
  before.flip_y != after.flip_y
}

///|
fn Slide::changed_member_transforms(
  self : Slide,
  before : Slide,
) -> Array[String] raise @failure.Failure {
  let previous : Map[String, Object] = Map([])
  for object in before.objects {
    previous[object.id] = object
  }
  self.objects
  .filter(object => {
    guard object.source.tree.part == self.tree.part &&
      !object.parent.is_empty() &&
      previous.get(object.id) is Some(old) &&
      old.parent == object.parent else {
      return false
    }
    let properties = if object.kind == "group" { "grpSpPr" } else { "spPr" }
    let transform = fn(object : Object) raise @failure.Failure {
      object.source
      .child(properties, uri=presentation_uri)
      .bind(properties => properties.child("xfrm"))
      .map(source_xml)
      .unwrap_or("")
    }
    transform(object) != transform(old)
  })
  .map(object => object.id)
}

///|
fn Slide::group_bounds(
  self : Slide,
  ids : Array[String],
) -> Slide raise @failure.Failure {
  let by_id : Map[String, Int] = Map([])
  let children : Map[String, Array[Int]] = Map([])
  for index, object in self.objects {
    by_id[object.id] = index
    if !object.parent.is_empty() {
      children.get_or_init(object.parent, () => []).push(index)
    }
  }
  let affected : Map[String, Bool] = Map([])
  for id in ids {
    let mut parent = self.object(id).parent
    while !parent.is_empty() {
      affected[parent] = true
      parent = self.objects[by_id[parent]].parent
    }
  }
  if affected.is_empty() {
    return self
  }
  let objects = self.objects.copy()
  // Postorder lets each parent's bounds include its already bounded child groups.
  for index, group in self.objects {
    if !affected.contains(group.id) {
      continue
    }
    let members = children.get(group.id).unwrap_or([])
    if members.is_empty() {
      continue
    }
    let mut left = 1.0 / 0.0
    let mut top = 1.0 / 0.0
    let mut right = -1.0 / 0.0
    let mut bottom = -1.0 / 0.0
    for child_index in members {
      let child = objects[child_index]
      guard child.geometry is Some(g) else {
        @failure.reject(
          "protected-content", "Group bounds require member geometry",
        )
      }
      let width = if g.resize_swaps_axes() { g.height } else { g.width }
      let height = if g.resize_swaps_axes() { g.width } else { g.height }
      left = left.min(g.x + (g.width - width) / 2)
      top = top.min(g.y + (g.height - height) / 2)
      right = right.max(g.x + (g.width + width) / 2)
      bottom = bottom.max(g.y + (g.height + height) / 2)
    }
    // ONLYOFFICE bounds member frames with the same quadrant axis exchange as resizing.
    left = (left * 12700).floor() / 12700
    top = (top * 12700).floor() / 12700
    let width = ((right * 12700).ceil() / 12700 - left).max(1.0 / 12700)
    let height = ((bottom * 12700).ceil() / 12700 - top).max(1.0 / 12700)
    let initial = group.geometry.unwrap()
    let child_matrix = group_matrix(group.source, initial)
    let sx = (child_matrix.a * child_matrix.a + child_matrix.b * child_matrix.b).sqrt()
    let sy = (child_matrix.c * child_matrix.c + child_matrix.d * child_matrix.d).sqrt()
    let frame = {
      ..child_matrix,
      a: child_matrix.a / sx,
      b: child_matrix.b / sx,
      c: child_matrix.c / sy,
      d: child_matrix.d / sy,
    }
    let (cx, cy) = frame.point(left + width / 2, top + height / 2)
    let parent = group.source.parent_frame()
    let (cx, cy) = parent.inverse().point(cx, cy)
    let x = cx - width / 2
    let y = cy - height / 2
    objects[index] = {
      ..group,
      geometry: Some({
        ..initial,
        x,
        y,
        width,
        height,
        matrix: parent.then(
          object_matrix(
            x,
            y,
            width,
            height,
            initial.rotation,
            initial.flip_x,
            initial.flip_y,
          ),
        ),
      }),
    }
  }
  { ..self, objects, }
}

///|
fn child_extent_changes(
  transform : Ref,
  name : String,
  x : Int64,
  y : Int64,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let keys = if name == "chOff" { ("x", "y") } else { ("cx", "cy") }
  if transform.child(name) is Some(child) {
    [(keys.0, x), (keys.1, y)]
    .filter(pair => child.node.attribute(pair.0) != Some(pair.1.to_string()))
    .map(pair => attribute_change(child, pair.0, pair.1.to_string()))
  } else {
    let xml = "<a:\{name} xmlns:a=\"\{drawing_uri}\" \{keys.0}=\"\{x}\" \{keys.1}=\"\{y}\"/>"
    if name == "chOff" && transform.child("chExt") is Some(next) {
      [
        {
          node: transform.node.id,
          offset: next.node.start - transform.node.start,
          length: 0,
          xml,
        },
      ]
    } else {
      [insertion(transform.node, xml)]
    }
  }
}

///|
fn Slide::normalized_group_changes(
  self : Slide,
  ids : Array[String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let bounded = self.group_bounds(ids)
  let roots : Array[Object] = []
  for id in ids {
    let mut object = self.object(id)
    while !object.parent.is_empty() {
      object = self.object(object.parent)
    }
    if !roots.any(root => root.id == object.id) {
      roots.push(object)
    }
  }
  let frames : Map[String, @layout.Matrix] = Map([])
  let changes : Array[@xml.SourceChange] = []
  // Reverse postorder writes parents before members, compensating rounded parent origins.
  for index = self.objects.length() - 1; index >= 0; index = index - 1 {
    let object = self.objects[index]
    if !roots.any(root => {
        root.id == object.id ||
        (
          root.source.tree.part == object.source.tree.part &&
          root.source.node.start < object.source.node.start &&
          root.source.node.end > object.source.node.end
        )
      }) {
      continue
    }
    guard object.geometry is Some(_) &&
      object.diagnostic.is_empty() &&
      ["shape", "image", "group"].contains(object.kind) else {
      @failure.reject(
        "protected-content", "Unknown group members prevent bounds normalization",
      )
    }
    if object.kind == "group" {
      let reason = object.source.group_problem()
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
    }
    let target = bounded.objects[index].geometry.unwrap()
    let parent = if object.parent.is_empty() {
      @layout.Matrix::identity()
    } else {
      frames[object.parent]
    }
    let width = (target.width * 12700).round() / 12700
    let height = (target.height * 12700).round() / 12700
    let (cx, cy) = target.matrix.point(target.width / 2, target.height / 2)
    let (cx, cy) = parent.inverse().point(cx, cy)
    let x = ((cx - width / 2) * 12700).round() / 12700
    let y = ((cy - height / 2) * 12700).round() / 12700
    guard [x, y, width, height].all(v => {
        !v.is_nan() && !v.is_inf() && v.abs() <= 14400
      }) &&
      (
        (width > 0 && height > 0) ||
        (
          object.preset == "line" &&
          width >= 0 &&
          height >= 0 &&
          width + height > 0
        )
      ) else {
      @failure.reject(
        "invalid-transform", "Normalized group coordinates exceed bounds",
      )
    }
    let native = { ..target, x, y, width, height, }
    changes.append(native_transform_changes(object, native))
    if object.kind == "group" {
      let transform = object.source
        .child("grpSpPr", uri=presentation_uri)
        .unwrap()
        .child("xfrm")
        .unwrap()
      changes.append(child_extent_changes(transform, "chOff", 0L, 0L))
      changes.append(
        child_extent_changes(
          transform,
          "chExt",
          (width * 12700).round().to_int64(),
          (height * 12700).round().to_int64(),
        ),
      )
      let actual = geometry_in_parent(
        x,
        y,
        width,
        height,
        target.rotation,
        target.flip_x,
        target.flip_y,
        parent,
      )
      frames[object.id] = actual.matrix.then({
        a: actual.width / width,
        b: 0,
        c: 0,
        d: actual.height / height,
        e: 0,
        f: 0,
      })
    }
  }
  changes
}

///|
fn Session::normalize_groups(
  self : Session,
  slide : Slide,
  main : Tree,
  index : Int,
  parts : Map[String, @xml.Document],
) -> (Slide, @xml.Edit?) raise @failure.Failure {
  guard self.slides
    .iter()
    .find_first(before => before.tree.part == slide.tree.part)
    is Some(before) else {
    return (slide, None)
  }
  let ids = slide.changed_member_transforms(before)
  if ids.is_empty() {
    return (slide, None)
  }
  // Prepared previews may already show new bounds; source still owns the original group axes.
  let source = read_slide(
    self.opc,
    main,
    self.cache,
    slide.tree,
    index~,
    parts~,
    date_time=self.date_time,
  )
  let changes = source.normalized_group_changes(ids)
  let (document, edit) = source.tree.document.edit_source(changes)
  if document.source() == source.tree.document.source() {
    return (slide, None)
  }
  (
    read_slide(
      self.opc,
      main,
      self.cache,
      Tree::new(slide.tree.part, document),
      index~,
      parts~,
      date_time=self.date_time,
    ),
    Some(edit),
  )
}
