///|
fn Session::group_members(
  self : Session,
  ungroup : Bool,
) -> Array[Object] raise @failure.Failure {
  guard self.candidate is None else {
    @failure.reject(
      "active-gesture", "Finish the current gesture before grouping",
    )
  }
  let objects = self.transform_objects()
  guard ungroup || objects.length() >= 2 else {
    @failure.reject("invalid-operation", "Select at least two objects to group")
  }
  let slide = self.current()
  let mut expanded = 0
  for object in objects {
    if ungroup {
      guard object.kind == "group" else {
        @failure.reject("invalid-operation", "Select groups to ungroup")
      }
      let properties = hyperlink_properties(object)
      guard properties.child("hlinkClick") is None &&
        properties.child("hlinkMouseOver") is None else {
        @failure.reject(
          "protected-content", "Remove group links before ungrouping",
        )
      }
      let children = slide.objects.filter(child => child.parent == object.id)
      expanded += children.length()
      guard expanded <= 256 else {
        @failure.reject(
          "limit-exceeded", "Ungrouping selection exceeds 256 members",
        )
      }
      for child in children {
        ignore(child.ungroup_geometry(object.geometry.unwrap()))
      }
      guard !children.is_empty() else {
        @failure.reject(
          "invalid-operation", "The group has no editable members",
        )
      }
    } else {
      guard object.table is None else {
        @failure.reject(
          "protected-content", "Grouped tables require table scaling support",
        )
      }
      guard placeholder(object.source) is None else {
        @failure.reject(
          "protected-content", "Inherited placeholders cannot be grouped",
        )
      }
    }
    for node in slide.tree.document.nodes() {
      let inside = node.start >= object.source.node.start &&
        node.end <= object.source.node.end
      if inside {
        guard [presentation_uri, drawing_uri].contains(node.uri) &&
          node.name != "extLst" else {
          @failure.reject(
            "protected-content", "Unknown object extensions prevent grouping",
          )
        }
        if node.name.has_suffix("Locks") &&
          flag(node, if ungroup { "noUngrp" } else { "noGrp" }) {
          @failure.reject("protected-content", "Object grouping is locked")
        }
      } else {
        // Grouping changes the coordinate owner; referenced timing/connectors need their own transaction.
        for attribute in node.attributes {
          if ["spid", "spId", "shapeId", "shapeIdRef"].contains(attribute.name) ||
            (["stCxn", "endCxn"].contains(node.name) && attribute.name == "id") {
            let referenced = object.source.tree.part +
              "#" +
              source_identity(attribute.value)
            if (ungroup && referenced == object.id) ||
              (
                !ungroup &&
                (
                  referenced == object.id ||
                  slide.objects.any(child => {
                    child.id == referenced &&
                    child.source.node.start > object.source.node.start &&
                    child.source.node.end < object.source.node.end
                  })
                )
              ) {
              @failure.reject(
                "protected-content", "Referenced objects require grouping support",
              )
            }
          }
        }
      }
    }
  }
  objects
}

///|
fn Session::group_edit_reason(self : Session, ungroup : Bool) -> String {
  try {
    ignore(self.group_members(ungroup))
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::group_changes(
  self : Session,
  id : String,
) -> (Array[@xml.SourceChange], Selection) raise @failure.Failure {
  let selected = self.group_members(false)
  let slide = self.current()
  let objects = slide.objects.filter(object => {
    selected.any(item => item.id == object.id)
  })
  let box = slide.selection_box(self.selection.objects)
  let x = (box.x * 12700).floor() / 12700
  let y = (box.y * 12700).floor() / 12700
  let width = (((box.x + box.width) * 12700).ceil() / 12700 - x).max(0.1)
  let height = (((box.y + box.height) * 12700).ceil() / 12700 - y).max(0.1)
  validate_object_box(x, y, width, height, false)
  let document = transformed_markup(
    slide,
    objects.map(object => {
      let geometry = object.geometry.unwrap()
      let target = { ..geometry, x: geometry.x - x, y: geometry.y - y, }
      validate_object_box(
        target.x,
        target.y,
        target.width,
        target.height,
        object.preset == "line",
      )
      (object, target)
    }),
  )
  let content = StringBuilder()
  for object in objects {
    content.write_string(
      slide.tree.standalone_markup(document, object.source.node.id),
    )
  }
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  let markup = "<p:grpSp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvGrpSpPr><p:cNvPr id=\"\{id}\" name=\"Group \{id}\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm></p:grpSpPr>\{content.to_string()}</p:grpSp>"
  let changes : Array[@xml.SourceChange] = []
  let parent = shape_tree(slide.tree)
  for object in objects {
    let node = object.source.node
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: if object.id == objects.last().unwrap().id {
        markup
      } else {
        ""
      },
    })
  }
  let identity = slide.tree.part + "#" + id
  (
    changes,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
  )
}

///|
fn Session::ungroup_changes(
  self : Session,
) -> (Array[@xml.SourceChange], Selection) raise @failure.Failure {
  let groups = self.group_members(true)
  let slide = self.current()
  let changes : Array[@xml.SourceChange] = []
  let selected : Array[String] = []
  let parent = shape_tree(slide.tree)
  for group in groups {
    let children = slide.objects.filter(child => child.parent == group.id)
    let document = transformed_markup(
      slide,
      children.map(child => {
        (child, child.ungroup_geometry(group.geometry.unwrap()))
      }),
    )
    let content = StringBuilder()
    // Keep comments and whitespace between children at the group's former layer.
    let mut cursor = group.source.node.opening_end
    for node in slide.tree.children.get(group.source.node.id).unwrap_or([]) {
      content.write_view(slide.tree.document.source()[cursor:node.start])
      if children.any(child => child.source.node.id == node.id) {
        content.write_string(slide.tree.standalone_markup(document, node.id))
      }
      cursor = node.end
    }
    content.write_view(
      slide.tree.document.source()[cursor:group.source.node.closing_start],
    )
    changes.push({
      node: parent.id,
      offset: group.source.node.start - parent.start,
      length: group.source.node.end - group.source.node.start,
      xml: content.to_string(),
    })
    selected.append(children.map(child => child.id))
  }
  guard selected.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Ungrouping selection exceeds 256 members",
    )
  }
  (
    changes,
    {
      ..self.selection,
      object: selected.last().unwrap(),
      objects: selected,
      mode: "object",
      anchor: 0,
      focus: 0,
    },
  )
}
