///|
fn Object::connector_changes(
  self : Object,
  start : ConnectorEnd,
  end : ConnectorEnd,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let g = connector_geometry(start, end, parent=self.source.parent_matrix())
  let g = if self.parent.is_empty() { g } else { self.local_geometry(g) }
  let (before_start, before_end) = self.connector_ends()
  // Compare native EMUs so an equivalent world projection does not create an empty edit.
  let same_links = before_start.target == start.target &&
    before_start.site == start.site &&
    before_end.target == end.target &&
    before_end.site == end.site
  let same_box = geometry([self.source], @layout.Matrix::identity(), false)
    .map(raw => !member_geometry_changed(raw, g))
    .unwrap_or(false)
  if (before_start == start && before_end == end) || (same_links && same_box) {
    return []
  }
  let properties = self.connector_properties()
  let changes = connector_transform_changes(self, g)
  for (name, point) in [("stCxn", start), ("endCxn", end)] {
    let markup = connector_link(point, name)
    if properties.child(name) is Some(node) {
      changes.push(paint_child_change(properties, Some(node.node), markup, []))
    }
  }
  let start_missing = properties.child("stCxn") is None
  let end_missing = properties.child("endCxn") is None
  if start_missing && end_missing {
    let markup = connector_link(start, "stCxn") + connector_link(end, "endCxn")
    if !markup.is_empty() {
      changes.push(insertion(properties.node, markup))
    }
  } else if start_missing && !start.target.is_empty() {
    changes.push(
      paint_child_change(properties, None, connector_link(start, "stCxn"), [
        "endCxn",
      ]),
    )
  } else if end_missing && !end.target.is_empty() {
    changes.push(insertion(properties.node, connector_link(end, "endCxn")))
  }
  changes
}

///|
fn connector_link(point : ConnectorEnd, name : String) -> String {
  if point.target.is_empty() {
    return ""
  }
  let id = point.target.split("#").last().unwrap_or("")
  "<a:\{name} xmlns:a=\"\{drawing_uri}\" id=\"\{id}\" idx=\"\{point.site}\"/>"
}

///|
fn connector_transform_changes(
  object : Object,
  g : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  // Derived endpoints can differ from the serialized pose; write each source axis once.
  let raw = geometry([object.source], @layout.Matrix::identity(), false).unwrap()
  native_transform_changes({ ..object, geometry: Some(raw), }, g)
}

///|
fn connector_axes_changes(
  object : Object,
  g : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  if object.source
    .child("spPr", uri=presentation_uri)
    .bind(p => p.child("xfrm"))
    is Some(transform) {
    for
      (key, value) in [
        ("rot", "0"),
        ("flipH", if g.flip_x { "1" } else { "0" }),
        ("flipV", if g.flip_y { "1" } else { "0" }),
      ] {
      if transform.node.attribute(key).unwrap_or("0") != value {
        changes.push(attribute_change(transform, key, value))
      }
    }
  }
  changes
}

///|
fn Session::edit_connector(
  self : Session,
  kind : String,
  start : ConnectorEnd,
  end : ConnectorEnd,
  insert : Bool,
) -> Json raise @failure.Failure {
  guard ["straight", "elbow"].contains(kind) else {
    @failure.reject("invalid-operation", "Unknown connector kind")
  }
  let slide = self.current()
  guard slide.read_only.is_empty() else {
    @failure.reject("protected-content", slide.read_only)
  }
  let owner = if insert {
    ""
  } else {
    slide.object(self.selection.object).parent
  }
  for point in [start, end] {
    if !point.target.is_empty() &&
      slide.objects
      .iter()
      .find_first(o => o.id == point.target)
      .map(o => o.parent) !=
      Some(owner) {
      @failure.reject(
        "protected-content", "Connections must share their coordinate owner",
      )
    }
  }
  let start = start.resolved(slide.objects)
  let end = end.resolved(slide.objects)
  for point in [start, end] {
    guard point.target.is_empty() ||
      point.target.has_prefix(slide.tree.part + "#") else {
      @failure.reject(
        "protected-content", "Connections must stay in the same source part",
      )
    }
  }
  let id = if insert { self.next_object_identity() } else { "" }
  let (changes, selection) = if insert {
    let markup = connector_markup(id, kind, start, end)
    (
      [object_insertion(slide.tree, markup)],
      {
        ..self.selection,
        object: slide.tree.part + "#" + id,
        objects: [slide.tree.part + "#" + id],
        mode: "object",
        anchor: 0,
        focus: 0,
      },
    )
  } else {
    guard self.selection.mode == "object" &&
      self.selection.objects.length() == 1 else {
      @failure.reject(
        "invalid-operation", "Select one connector before editing endpoints",
      )
    }
    let object = slide.object(self.selection.object)
    let reason = self.object_edit_reason(object, "endpoints")
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let changes = object.connector_changes(start, end)
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let geometry = properties.child("prstGeom").unwrap()
    let preset = if kind == "elbow" {
      "bentConnector3"
    } else {
      "straightConnector1"
    }
    if (object.preset == "bentConnector3") != (kind == "elbow") {
      guard !object.source.tree.document
        .nodes()
        .any(node => {
          node.start >= object.source.node.start &&
          node.end <= object.source.node.end &&
          node.name.has_suffix("Locks") &&
          flag(node, "noChangeShapeType")
        }) else {
        @failure.reject("protected-content", "Connector type editing is locked")
      }
      let source = source_xml(geometry)
      guard !source.contains("<!--") &&
        !source.contains("<?") &&
        geometry.node.attributes.all(a => a.uri.is_empty() && a.name == "prst") &&
        geometry.node.text.trim().is_empty() &&
        geometry.tree.children
        .get(geometry.node.id)
        .unwrap_or([])
        .all(list => {
          list.uri == drawing_uri &&
          list.name == "avLst" &&
          list.attributes.is_empty() &&
          list.text.trim().is_empty() &&
          geometry.tree.children
          .get(list.id)
          .unwrap_or([])
          .all(node => {
            node.uri == drawing_uri &&
            node.name == "gd" &&
            node.text.trim().is_empty() &&
            node.attributes.all(a => {
              a.uri.is_empty() && ["name", "fmla"].contains(a.name)
            }) &&
            geometry.tree.children.get(node.id).unwrap_or([]).is_empty()
          })
        }) else {
        @failure.reject(
          "protected-content", "Retained connector geometry is protected",
        )
      }
      changes.push(
        paint_child_change(
          properties,
          Some(geometry.node),
          "<a:prstGeom xmlns:a=\"\{drawing_uri}\" prst=\"\{preset}\"><a:avLst/></a:prstGeom>",
          [],
        ),
      )
    }
    (changes, self.selection)
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare(slide, changes)
  self.commit(candidate, edit, selection)
  if insert {
    self.object_sequence = number(id, 1, 4294967295).to_int64() + 1L
  }
  self.query()
}

///|
fn Slide::connector_bounds(
  self : Slide,
  before : Slide,
) -> Slide raise @failure.Failure {
  let objects = self.objects.map(object => {
    if object.source.node.name != "cxnSp" ||
      object.source.tree.part != self.tree.part {
      return object
    }
    let moved = object
      .connector_targets()
      .any(target => {
        let old = before.objects.iter().find_first(o => o.id == target)
        let next = self.objects.iter().find_first(o => o.id == target)
        old is Some(old) &&
        next is Some(next) &&
        old.geometry is Some(a) &&
        next.geometry is Some(b) &&
        connector_frame_changed(a, b)
      })
    if !moved {
      return object
    }
    guard ["", "Group members are read-only"].contains(object.read_only) else {
      @failure.reject(
        "protected-content", "A protected connector prevents moving its target",
      )
    }
    let (start, end) = object.connector_ends()
    // Displayed member axes stay stable when a virtual parent box is bounded again.
    let g = object.geometry.unwrap()
    let parent = g.matrix.then(
      object_matrix(g.x, g.y, g.width, g.height, g.rotation, g.flip_x, g.flip_y).inverse(),
    )
    {
      ..object,
      geometry: Some(
        connector_geometry(
          start.resolved(self.objects),
          end.resolved(self.objects),
          parent~,
        ),
      ),
    }
  })
  { ..self, objects, }
}

///|
fn Session::normalize_connectors(
  self : Session,
  slide : Slide,
  main : Tree,
  index : Int,
  parts : Map[String, @xml.Document],
) -> (Slide, @xml.Edit?) raise @failure.Failure {
  let before = if self.slides
    .iter()
    .find_first(s => s.tree.part == slide.tree.part)
    is Some(before) {
    before
  } else if ["sldMaster", "sldLayout"].contains(
      slide.tree.document.nodes()[0].name,
    ) {
    self.source_slide(slide.tree.part)
  } else {
    return (slide, None)
  }
  let bounded = slide.connector_bounds(before)
  let changed = bounded.objects.filter_map(object => {
    if object.source.node.name != "cxnSp" ||
      object.source.tree.part != slide.tree.part ||
      !["", "Group members are read-only"].contains(object.read_only) {
      return None
    }
    let raw = geometry([object.source], object.source.parent_matrix(), false).unwrap()
    if connector_frame_changed(raw, object.geometry.unwrap()) {
      Some((object, object.geometry.unwrap()))
    } else {
      None
    }
  })
  if changed.is_empty() {
    return (slide, None)
  }
  let members = changed
    .filter(pair => !pair.0.parent.is_empty())
    .map(pair => pair.0.id)
  let changes = bounded.normalized_group_changes(members)
  for (object, g) in changed {
    if object.parent.is_empty() {
      changes.append(connector_transform_changes(object, g))
    } else {
      changes.append(connector_axes_changes(object, g))
    }
  }
  let (document, edit) = slide.tree.document.edit_source(changes)
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

///|
fn connector_markup(
  id : String,
  kind : String,
  start : ConnectorEnd,
  end : ConnectorEnd,
) -> String raise @failure.Failure {
  let g = connector_geometry(start, end)
  let preset = if kind == "elbow" {
    "bentConnector3"
  } else {
    "straightConnector1"
  }
  let markup = "<p:cxnSp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvCxnSpPr><p:cNvPr id=\"\{id}\" name=\"Connector \{id}\"/><p:cNvCxnSpPr>\{connector_link(start, "stCxn")}\{connector_link(end, "endCxn")}</p:cNvCxnSpPr><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm flipH=\"\{if g.flip_x { 1 } else { 0 }}\" flipV=\"\{if g.flip_y { 1 } else { 0 }}\"><a:off x=\"\{(g.x * 12700).round().to_int64()}\" y=\"\{(g.y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(g.width * 12700).round().to_int64()}\" cy=\"\{(g.height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom><a:noFill/><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln></p:spPr></p:cxnSp>"
  markup
}
