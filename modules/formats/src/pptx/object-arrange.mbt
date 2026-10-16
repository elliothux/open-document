///|
fn Session::arrange_object(
  self : Session,
  object : Object,
  change : ObjectEdit,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let action = if change is Rotate(_) { "rotate" } else { "arrange" }
  let reason = self.object_edit_reason(object, action)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let geometry = object.geometry.unwrap()
  let tree = object.source.tree
  if change is Layer(direction) {
    guard ["front", "back", "forward", "backward"].contains(direction) else {
      @failure.reject("invalid-operation", "Unknown object layer operation")
    }
    let parent = shape_tree(tree)
    let peers = tree.children
      .get(parent.id)
      .unwrap_or([])
      .filter(node => {
        node.uri != presentation_uri ||
        !["nvGrpSpPr", "grpSpPr", "extLst"].contains(node.name)
      })
    let index = peers
      .search_by(node => node.start == object.source.node.start)
      .unwrap()
    let target = match direction {
      "front" => peers.length() - 1
      "back" => 0
      "forward" => (index + 1).min(peers.length() - 1)
      _ => (index - 1).max(0)
    }
    if target == index {
      return []
    }
    let node = object.source.node
    let offset = if target < index {
      peers[target].start
    } else {
      peers[target].end
    }
    return [
      {
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: "",
      },
      {
        node: parent.id,
        offset: offset - parent.start,
        length: 0,
        xml: source_xml(object.source),
      },
    ]
  }
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
    let changes : Array[@xml.SourceChange] = []
    for
      (name, before, after) in [
        (
          "rot",
          (geometry.rotation * 60000).round().to_int64().to_string(),
          (rotation * 60000).round().to_int64().to_string(),
        ),
        (
          "flipH",
          if geometry.flip_x {
            "1"
          } else {
            "0"
          },
          if flip_x {
            "1"
          } else {
            "0"
          },
        ),
        (
          "flipV",
          if geometry.flip_y {
            "1"
          } else {
            "0"
          },
          if flip_y {
            "1"
          } else {
            "0"
          },
        ),
      ] {
      if before != after {
        changes.push(attribute_change(transform, name, after))
      }
    }
    changes
  } else {
    transform_changes(object, { ..geometry, rotation, flip_x, flip_y, })
  }
}
