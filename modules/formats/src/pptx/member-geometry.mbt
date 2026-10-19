///|
fn Ref::parent_frame(self : Ref) -> @layout.Matrix raise @failure.Failure {
  let parent = self.parent_matrix()
  let sx = (parent.a * parent.a + parent.b * parent.b).sqrt()
  let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
  {
    ..parent,
    a: parent.a / sx,
    b: parent.b / sx,
    c: parent.c / sy,
    d: parent.d / sy,
  }
}

///|
fn Object::local_geometry(
  self : Object,
  target : Geometry,
) -> Geometry raise @failure.Failure {
  let parent = self.source.parent_matrix()
  let sx = (parent.a * parent.a + parent.b * parent.b).sqrt()
  let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
  let result = {
    ..target,
    x: (target.x / sx * 12700).round() / 12700,
    y: (target.y / sy * 12700).round() / 12700,
    width: (target.width / sx * 12700).round() / 12700,
    height: (target.height / sy * 12700).round() / 12700,
  }
  guard [result.x, result.y, result.width, result.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 14400
    }) &&
    (
      (result.width > 0 && result.height > 0) ||
      (
        self.preset == "line" &&
        result.width >= 0 &&
        result.height >= 0 &&
        result.width + result.height > 0
      )
    ) else {
    @failure.reject(
      "invalid-transform", "Native member geometry exceeds bounds",
    )
  }
  result
}

///|
fn Object::placed_geometry(
  self : Object,
  target : Geometry,
) -> Geometry raise @failure.Failure {
  if self.parent.is_empty() {
    return {
      ..target,
      matrix: object_matrix(
        target.x,
        target.y,
        target.width,
        target.height,
        target.rotation,
        target.flip_x,
        target.flip_y,
      ),
    }
  }
  let native = self.local_geometry(target)
  geometry_in_parent(
    native.x,
    native.y,
    native.width,
    native.height,
    native.rotation,
    native.flip_x,
    native.flip_y,
    self.source.parent_matrix(),
  )
}

///|
fn Object::member_transform_reason(
  self : Object,
  action : String,
) -> String raise @failure.Failure {
  for parent = self.source.node.parent
      parent >= 0
      parent = self.source.tree.nodes[parent].parent {
    let node = self.source.tree.nodes[parent]
    if node.uri != presentation_uri || node.name != "grpSp" {
      continue
    }
    let group : Ref = { tree: self.source.tree, node, }
    let problem = group.group_problem()
    if !problem.is_empty() {
      return problem
    }
    let locks = group
      .child("nvGrpSpPr", uri=presentation_uri)
      .bind(nv => nv.child("cNvGrpSpPr", uri=presentation_uri))
      .bind(properties => properties.child("grpSpLocks"))
    if locks is Some(locks) &&
      ["noDrilldown", "noSelect", "noMove", "noResize"].any(key => {
        flag(locks.node, key)
      }) {
      return "Group member transforms are locked"
    }
    if locks is Some(locks) && action == "rotate" && flag(locks.node, "noRot") {
      return "Group member rotation is locked"
    }
    if locks is Some(locks) &&
      (
        (action == "duplicate" && flag(locks.node, "noCopy")) ||
        (action == "delete" && flag(locks.node, "noDelete"))
      ) {
      return "Group member operation is locked: " + action
    }
    if locks is Some(locks) &&
      (
        (action == "group" && flag(locks.node, "noGrp")) ||
        (action == "ungroup" && flag(locks.node, "noUngrp"))
      ) {
      return "Group member grouping is locked"
    }
  }
  ""
}

///|
fn transform_changes(
  object : Object,
  target : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  native_transform_changes(
    object,
    if object.parent.is_empty() {
      target
    } else {
      object.local_geometry(target)
    },
  )
}
