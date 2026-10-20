///|
fn check_collapsed_group(group : Object) -> Unit raise @failure.Failure {
  let properties = hyperlink_properties(group)
  guard properties.child("hlinkClick") is None &&
    properties.child("hlinkMouseOver") is None else {
    @failure.reject(
      "protected-content", "Remove group links before deleting its last members",
    )
  }
  let locks = group.source
    .child("nvGrpSpPr", uri=presentation_uri)
    .bind(nv => nv.child("cNvGrpSpPr", uri=presentation_uri))
    .bind(nv => nv.child("grpSpLocks"))
  if locks is Some(locks) &&
    ["noUngrp", "noDelete"].any(key => flag(locks.node, key)) {
    @failure.reject("protected-content", "Group removal is locked")
  }
  let identity = group.id.split("#").last().unwrap().to_owned()
  for node in group.source.tree.document.nodes() {
    for attribute in node.attributes {
      if (
          ["spid", "spId", "shapeId", "shapeIdRef"].contains(attribute.name) ||
          (["stCxn", "endCxn"].contains(node.name) && attribute.name == "id")
        ) &&
        source_identity(attribute.value) == identity {
        @failure.reject(
          "protected-content", "Referenced groups cannot collapse during deletion",
        )
      }
    }
  }
}

///|
fn deletion_markup(
  object : Object,
  document : @xml.Document,
  children : Map[String, Array[Object]],
  removed : Map[String, Bool],
  collapsed : Map[String, Object],
  affected : Map[String, Bool],
) -> String raise @failure.Failure {
  if removed.contains(object.id) {
    return ""
  }
  if collapsed.get(object.id) is Some(child) {
    let output = StringBuilder()
    let node = document.node(object.source.node.id)
    let mut cursor = node.opening_end
    for
      original in object.source.tree.children
      .get(object.source.node.id)
      .unwrap_or([]) {
      let item = document.node(original.id)
      output.write_view(document.source()[cursor:item.start])
      if original.id == child.source.node.id {
        output.write_string(
          deletion_markup(
            child, document, children, removed, collapsed, affected,
          ),
        )
      }
      cursor = item.end
    }
    output.write_view(document.source()[cursor:node.closing_start])
    return output.to_string()
  }
  let tree = object.source.tree
  let mut markup = tree.standalone_markup(document, object.source.node.id)
  for child in children.get(object.id).unwrap_or([]) {
    if !affected.contains(child.id) {
      continue
    }
    let node = document.node(child.source.node.id)
    markup = markup.replace(
      old=document.source()[node.start:node.end].to_owned(),
      new=deletion_markup(
        child, document, children, removed, collapsed, affected,
      ),
    )
  }
  markup
}

///|
fn Slide::deletion_plan(
  slide : Slide,
  selected : Array[Object],
) -> (
  Map[String, Array[Object]],
  Map[String, Bool],
  Map[String, Object],
  Map[String, Bool],
) raise @failure.Failure {
  let children : Map[String, Array[Object]] = Map([])
  let by_id : Map[String, Object] = Map([])
  for object in slide.objects {
    by_id[object.id] = object
    children.get_or_init(object.parent, () => []).push(object)
  }
  let removed : Map[String, Bool] = Map([])
  let affected : Map[String, Bool] = Map([])
  for object in selected {
    removed[object.id] = true
    affected[object.id] = true
    let mut parent = object.parent
    while !parent.is_empty() {
      affected[parent] = true
      parent = by_id[parent].parent
    }
  }
  let collapsed : Map[String, Object] = Map([])
  // Postorder removes empty groups and promotes their sole surviving member.
  for object in slide.objects {
    if object.kind != "group" ||
      !affected.contains(object.id) ||
      removed.contains(object.id) {
      continue
    }
    let survivors = children
      .get(object.id)
      .unwrap_or([])
      .filter(child => !removed.contains(child.id))
    if survivors.length() <= 1 {
      check_collapsed_group(object)
      if survivors.is_empty() {
        removed[object.id] = true
      } else {
        collapsed[object.id] = survivors[0]
      }
    }
  }
  (children, removed, collapsed, affected)
}

///|
fn Session::deletion_group_reason(self : Session) -> String {
  if self.selection.mode != "object" {
    return ""
  }
  try {
    let slide = self.current()
    let selected = self.selection.objects.map(id => slide.object(id))
    if selected.any(object => !object.parent.is_empty()) {
      ignore(slide.deletion_plan(selected))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::remove_objects(
  self : Session,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let selected = self.transform_objects(action="delete")
  let slide = self.current()
  let (children, removed, collapsed, affected) = slide.deletion_plan(selected)
  let by_id : Map[String, Object] = Map([])
  for object in slide.objects {
    by_id[object.id] = object
  }
  let promoted : Array[(Object, Geometry)] = []
  for object in slide.objects {
    if removed.contains(object.id) || collapsed.contains(object.id) {
      continue
    }
    let mut parent = object.parent
    let mut flip_x = object.geometry.map(g => g.flip_x).unwrap_or(false)
    while collapsed.contains(parent) {
      let group = by_id[parent]
      flip_x = flip_x != group.geometry.unwrap().flip_x
      parent = group.parent
    }
    if parent == object.parent {
      continue
    }
    let matrix = if parent.is_empty() {
      @layout.Matrix::identity()
    } else {
      let group = by_id[parent]
      group_matrix(group.source, group.geometry.unwrap())
    }
    promoted.push((object, object.promoted_geometry(matrix, flip_x)))
  }
  let document = transformed_markup(slide, promoted)
  let root = shape_tree(slide.tree)
  let changes : Array[@xml.SourceChange] = children
    .get("")
    .unwrap_or([])
    .filter(object => {
      object.source.tree.part == slide.tree.part && affected.contains(object.id)
    })
    .map(object => {
      node: root.id,
      offset: object.source.node.start - root.start,
      length: object.source.node.end - object.source.node.start,
      xml: deletion_markup(
        object, document, children, removed, collapsed, affected,
      ),
    })
  if has_media_settings(slide.tree, removed.keys().to_array()) {
    let media = read_media_nodes(slide.tree)
    let remaining : Map[String, (String, MediaPlaybackSettings)] = Map([])
    for id, value in media {
      if !removed.contains(id) {
        remaining[id] = value
      }
    }
    changes.push(
      self.animation_change(slide, self.read_animations(slide), remaining),
    )
  }
  changes
}
