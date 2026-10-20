///|
fn Ref::parent_group(self : Ref) -> String raise @failure.Failure {
  if self.tree.nodes.get(self.node.parent) is Some(parent) &&
    parent.uri == presentation_uri &&
    parent.name == "grpSp" {
    let nv = self.tree.required(parent.id, "nvGrpSpPr", uri=presentation_uri)
    let identity = self.tree.required(nv.id, "cNvPr", uri=presentation_uri)
    self.tree.part +
    "#" +
    source_identity(identity.attribute("id").unwrap_or(""))
  } else {
    ""
  }
}

///|
fn Ref::group_problem(self : Ref) -> String raise @failure.Failure {
  if !self.node.attributes.is_empty() {
    return "Unsupported group attributes"
  }
  for node in self.tree.children.get(self.node.id).unwrap_or([]) {
    if node.uri != presentation_uri ||
      !["nvGrpSpPr", "grpSpPr", "sp", "pic", "grpSp", "cxnSp"].contains(
        node.name,
      ) {
      return "Unsupported group member or metadata"
    }
    if node.name == "grpSpPr" &&
      self.tree.children
      .get(node.id)
      .unwrap_or([])
      .any(child => child.uri != drawing_uri || child.name != "xfrm") {
      return "Group paint and effects require editing support"
    }
    if node.name == "nvGrpSpPr" {
      for child in self.tree.children.get(node.id).unwrap_or([]) {
        if child.uri != presentation_uri ||
          !["cNvPr", "cNvGrpSpPr", "nvPr"].contains(child.name) {
          return "Unsupported group metadata"
        }
        if child.name != "cNvGrpSpPr" &&
          self.tree.children
          .get(child.id)
          .unwrap_or([])
          .any(node => {
            child.name != "cNvPr" ||
            node.uri != drawing_uri ||
            !["hlinkClick", "hlinkMouseOver"].contains(node.name)
          }) {
          return "Group metadata requires editing support"
        }
        if child.name == "cNvPr" && flag(child, "hidden") {
          return "Hidden groups require visibility support"
        }
      }
    }
  }
  ""
}

///|
fn Ref::group_text_reason(self : Ref) -> String raise @failure.Failure {
  let locks = self
    .child("nvGrpSpPr", uri=presentation_uri)
    .bind(nv => nv.child("cNvGrpSpPr", uri=presentation_uri))
    .bind(properties => properties.child("grpSpLocks"))
  if locks is Some(locks) &&
    ["noDrilldown", "noSelect", "noTextEdit"].any(key => flag(locks.node, key)) {
    "Group text editing is locked"
  } else {
    ""
  }
}

///|
fn Ref::parent_matrix(self : Ref) -> @layout.Matrix raise @failure.Failure {
  let ancestors : Array[Ref] = []
  for parent = self.node.parent
      parent >= 0
      parent = self.tree.nodes[parent].parent {
    let node = self.tree.nodes[parent]
    if node.uri == presentation_uri && node.name == "grpSp" {
      ancestors.push({ tree: self.tree, node, })
    }
  }
  let mut matrix = @layout.Matrix::identity()
  for group in ancestors.rev() {
    let transform = geometry([group], matrix, true).unwrap()
    matrix = group_matrix(group, transform)
  }
  matrix
}

///|
fn Slide::group_preview(
  self : Slide,
  objects : Array[Object],
) -> Slide raise @failure.Failure {
  let changed : Map[String, Bool] = Map([])
  // Objects are read in postorder, so update parents before their nested groups.
  for index = self.objects.length() - 1; index >= 0; index = index - 1 {
    let group = self.objects[index]
    if group.kind != "group" || !(group.geometry is Some(_)) {
      continue
    }
    let before = group.geometry.unwrap()
    let after = objects[index].geometry.unwrap()
    if before.x == after.x &&
      before.y == after.y &&
      before.width == after.width &&
      before.height == after.height &&
      !changed.contains(group.id) {
      continue
    }
    let old_parent = group_matrix(group.source, before)
    let parent = group_matrix(group.source, after)
    let sx = (old_parent.a * old_parent.a + old_parent.b * old_parent.b).sqrt()
    let sy = (old_parent.c * old_parent.c + old_parent.d * old_parent.d).sqrt()
    for member_index, child in self.objects {
      if child.parent == group.id && child.geometry is Some(geometry) {
        objects[member_index] = {
          ..objects[member_index],
          geometry: Some(
            geometry_in_parent(
              geometry.x / sx,
              geometry.y / sy,
              geometry.width / sx,
              geometry.height / sy,
              geometry.rotation,
              geometry.flip_x,
              geometry.flip_y,
              parent,
            ),
          ),
        }
        changed[child.id] = true
      }
    }
  }
  { ..self, objects, }
}

///|
fn Tree::standalone_markup(
  self : Tree,
  document : @xml.Document,
  id : Int,
) -> String raise @failure.Failure {
  let ancestors : Array[Int] = []
  for parent = self.nodes[id].parent
      parent >= 0
      parent = self.nodes[parent].parent {
    ancestors.push(parent)
  }
  let bindings : Map[String, String] = Map([])
  for ancestor in ancestors.rev() {
    for (prefix, uri) in self.nodes[ancestor].namespaces {
      bindings[prefix] = uri
    }
  }
  let node = document.node(id)
  let extra = StringBuilder()
  for prefix, uri in bindings {
    if !node.namespaces.any(binding => binding.0 == prefix) {
      extra.write_string(
        " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{xml_attribute(uri)}\"",
      )
    }
  }
  let offset = node.opening_end - (if node.empty { 2 } else { 1 })
  document.source()[node.start:offset].to_owned() +
  extra.to_string() +
  document.source()[offset:node.end].to_owned()
}

///|
fn transformed_markup(
  original : Slide,
  objects : Array[(Object, Geometry)],
) -> @xml.Document raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  for (object, target) in objects {
    changes.append(native_transform_changes(object, target))
  }
  original.tree.document.edit_source(changes).0
}

///|
fn Object::promoted_geometry(
  self : Object,
  parent : @layout.Matrix,
  flip_x : Bool,
) -> Geometry raise @failure.Failure {
  let initial = self.geometry.unwrap()
  let matrix = initial.matrix
  guard (matrix.a * matrix.a + matrix.b * matrix.b - 1).abs() < 0.00000001 &&
    (matrix.c * matrix.c + matrix.d * matrix.d - 1).abs() < 0.00000001 &&
    (matrix.a * matrix.c + matrix.b * matrix.d).abs() < 0.00000001 else {
    @failure.reject("protected-content", "Unsupported group member transform")
  }
  let sx = (parent.a * parent.a + parent.b * parent.b).sqrt()
  let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
  let frame = {
    ..parent,
    a: parent.a / sx,
    b: parent.b / sx,
    c: parent.c / sy,
    d: parent.d / sy,
  }
  let relative = frame.inverse().then(initial.matrix)
  let sign = if flip_x { -1.0 } else { 1.0 }
  let rotation = (@math.atan2(relative.b * sign, relative.a * sign) *
    180 /
    @math.PI *
    60000).round() /
    60000
  let flip_y = (relative.a * relative.d - relative.b * relative.c < 0) != flip_x
  let (cx, cy) = initial.matrix.point(initial.width / 2, initial.height / 2)
  let (cx, cy) = frame.inverse().point(cx, cy)
  let target = {
    ..initial,
    x: ((cx - initial.width / 2) / sx * 12700).round() / 12700,
    y: ((cy - initial.height / 2) / sy * 12700).round() / 12700,
    width: (initial.width / sx * 12700).round() / 12700,
    height: (initial.height / sy * 12700).round() / 12700,
    rotation,
    flip_x,
    flip_y,
  }
  guard [target.x, target.y, target.width, target.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 14400
    }) &&
    (
      (target.width > 0 && target.height > 0) ||
      (
        self.preset == "line" &&
        target.width >= 0 &&
        target.height >= 0 &&
        target.width + target.height > 0
      )
    ) else {
    @failure.reject(
      "invalid-transform", "Promoted group member exceeds native bounds",
    )
  }
  target
}
