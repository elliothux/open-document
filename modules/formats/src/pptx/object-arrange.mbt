///|
fn Ref::pose_changes(
  self : Ref,
  before : Geometry,
  after : Geometry,
) -> Array[@xml.SourceChange] {
  let changes : Array[@xml.SourceChange] = []
  for
    (name, changed, value) in [
      (
        "rot",
        before.rotation != after.rotation,
        (after.rotation * 60000).round().to_int64().to_string(),
      ),
      (
        "flipH",
        before.flip_x != after.flip_x,
        if after.flip_x {
          "1"
        } else {
          "0"
        },
      ),
      (
        "flipV",
        before.flip_y != after.flip_y,
        if after.flip_y {
          "1"
        } else {
          "0"
        },
      ),
    ] {
    if changed {
      changes.push(attribute_change(self, name, value))
    }
  }
  changes
}

///|
fn Session::arrange_object(
  self : Session,
  object : Object,
  change : ObjectEdit,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let action = if change is Rotate(_) { "rotate" } else { "flip" }
  let reason = self.object_edit_reason(object, action)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let geometry = object.geometry.unwrap()
  let tree = object.source.tree
  let (rotation, flip_x, flip_y) = match change {
    Rotate(angle) => {
      guard !angle.is_nan() && !angle.is_inf() && angle.abs() <= 360 else {
        @failure.reject(
          "invalid-transform", "Rotation must be within -360 and 360 degrees",
        )
      }
      ((angle * 60000).round() / 60000, geometry.flip_x, geometry.flip_y)
    }
    Flip(horizontal) =>
      (
        geometry.rotation,
        if horizontal {
          !geometry.flip_x
        } else {
          geometry.flip_x
        },
        if horizontal {
          geometry.flip_y
        } else {
          !geometry.flip_y
        },
      )
    _ => @failure.reject("invalid-operation", "Unknown orientation operation")
  }
  if rotation == geometry.rotation &&
    flip_x == geometry.flip_x &&
    flip_y == geometry.flip_y {
    return []
  }
  let properties = object.source
    .child(
      if object.kind == "group" {
        "grpSpPr"
      } else {
        "spPr"
      },
      uri=presentation_uri,
    )
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part=tree.part,
        offset=-1,
        message="Missing editable shape properties",
      ),
    )
  if properties.child("xfrm") is Some(transform) {
    transform.pose_changes(geometry, { ..geometry, rotation, flip_x, flip_y, })
  } else {
    transform_changes(object, { ..geometry, rotation, flip_x, flip_y, })
  }
}

///|
fn Session::layer_objects(
  self : Session,
  direction : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard ["front", "back", "forward", "backward"].contains(direction) else {
    @failure.reject("invalid-operation", "Unknown object layer operation")
  }
  let objects = self.transform_objects()
  let tree = self.current().tree
  let parent = tree.nodes[objects[0].source.node.parent]
  let peers = tree.children
    .get(parent.id)
    .unwrap_or([])
    .filter(node => {
      node.uri != presentation_uri ||
      !["nvGrpSpPr", "grpSpPr", "extLst"].contains(node.name)
    })
  let selected : Map[Int32, Bool] = Map([])
  for object in objects {
    selected[object.source.node.id] = true
  }
  let ordered = if direction == "front" {
    [
      ..peers.filter(node => !selected.contains(node.id)),
      ..peers.filter(node => selected.contains(node.id)),
    ]
  } else if direction == "back" {
    [
      ..peers.filter(node => selected.contains(node.id)),
      ..peers.filter(node => !selected.contains(node.id)),
    ]
  } else {
    let ordered = peers.copy()
    for step in 0..<(peers.length() - 1) {
      let index = if direction == "forward" {
        peers.length() - 2 - step
      } else {
        step
      }
      let left = ordered[index]
      let right = ordered[index + 1]
      if (
          direction == "forward" &&
          selected.contains(left.id) &&
          !selected.contains(right.id)
        ) ||
        (
          direction == "backward" &&
          !selected.contains(left.id) &&
          selected.contains(right.id)
        ) {
        ordered[index] = right
        ordered[index + 1] = left
      }
    }
    ordered
  }
  if peers.map(node => node.id) == ordered.map(node => node.id) {
    return []
  }
  let changes : Array[@xml.SourceChange] = objects.map(object => {
    let node = object.source.node
    {
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: "",
    }
  })
  let pending = StringBuilder()
  let mut last = parent.opening_end
  for node in ordered {
    if selected.contains(node.id) {
      pending.write_view(tree.document.source()[node.start:node.end])
    } else {
      if !pending.is_empty() {
        changes.push({
          node: parent.id,
          offset: node.start - parent.start,
          length: 0,
          xml: pending.to_string(),
        })
        pending.reset()
      }
      last = node.end
    }
  }
  if !pending.is_empty() {
    changes.push({
      node: parent.id,
      offset: last - parent.start,
      length: 0,
      xml: pending.to_string(),
    })
  }
  changes
}
