///|
fn SheetObject::transfer_identity(
  self : SheetObject,
  copy : Bool,
) -> @xml.Node raise @failure.Failure {
  let object = self
  object.check_change(false)
  let tree = object.tree
  let nv_name = if object.chart is Some(_) {
    "nvGraphicFramePr"
  } else if object.shape is Some(_) {
    "nvSpPr"
  } else {
    "nvPicPr"
  }
  let nv = tree.picture_node(object.source.id, nv_name)
  let identity = tree.picture_node(nv.id, "cNvPr")
  guard identity.attributes.all(a => {
      a.uri.is_empty() &&
      ["id", "name", "descr", "title", "hidden"].contains(a.name)
    }) &&
    tree.children.get(identity.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "protected-content", "Drawing identity extensions require copy remapping",
    )
  }
  let rel_uri = relationship_uri[:relationship_uri.length() - 1].to_owned()
  for node in tree.document.nodes() {
    if node.start < object.source.start || node.end > object.source.end {
      continue
    }
    guard !node.name.has_suffix("Locks") ||
      !flag(node, if copy { "noCopy" } else { "noMove" }) else {
      @failure.reject(
        "protected-content", "Worksheet drawing copying is locked",
      )
    }
    guard node.attributes.all(a => {
        a.uri != rel_uri ||
        (
          object.media is Some(_) &&
          node.uri == picture_drawing_uri &&
          node.name == "blip" &&
          a.name == "embed"
        ) ||
        (
          object.chart is Some(_) &&
          node.uri == chart_uri &&
          node.name == "chart" &&
          a.name == "id"
        )
      }) &&
      (
        node.parent != nv.id ||
        ["cNvPr", "cNvPicPr", "cNvSpPr", "cNvGraphicFramePr", "nvPr"].contains(
          node.name,
        )
      ) else {
      @failure.reject(
        "protected-content", "Drawing references require copy remapping",
      )
    }
    if node.parent == nv.id && node.name != "cNvPr" {
      guard node.attributes.all(a => {
          a.uri.is_empty() && node.name == "cNvSpPr" && a.name == "txBox"
        }) &&
        tree.children
        .get(node.id)
        .unwrap_or([])
        .all(child => {
          child.uri == picture_drawing_uri &&
          child.name.has_suffix("Locks") &&
          tree.children.get(child.id).unwrap_or([]).is_empty()
        }) else {
        @failure.reject(
          "protected-content", "Drawing metadata requires copy remapping",
        )
      }
    }
  }
  identity
}

///|
fn SheetObject::transfer_changes(
  self : SheetObject,
  identity : @xml.Node,
  next_id : String,
  rect : @layout.Border,
  dimensions : Dimensions,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let object = self
  let tree = self.tree
  let changes = metadata_changes(identity, [("id", next_id)])
  // Patch coordinates in place so copied source annotations and native locks survive.
  if object.anchor == "fixed" {
    changes.append(
      metadata_changes(tree.picture_node(object.frame.id, "pos"), [
        ("x", picture_emu(rect.x)),
        ("y", picture_emu(rect.y)),
      ]),
    )
  } else {
    for
      (name, x, y) in [
        ("from", rect.x, rect.y),
        ("to", rect.x + rect.width, rect.y + rect.height),
      ] {
      if name == "to" && object.anchor != "size" {
        continue
      }
      let marker = tree.picture_node(object.frame.id, name)
      let col = dimensions.columns.locate(x)
      let row = dimensions.rows.locate(y)
      for
        (field, value) in [
          ("col", (col - 1).to_string()),
          ("row", (row - 1).to_string()),
          ("colOff", picture_emu(x - dimensions.columns.position(col))),
          ("rowOff", picture_emu(y - dimensions.rows.position(row))),
        ] {
        changes.append(
          axis_text_change(tree, tree.picture_node(marker.id, field), value),
        )
      }
    }
  }
  let props = if object.chart is Some(_) {
    object.source
  } else {
    tree.picture_node(object.source.id, "spPr")
  }
  if tree.picture_child(
      props.id,
      "xfrm",
      uri=if object.chart is Some(_) {
        picture_uri
      } else {
        picture_drawing_uri
      },
    )
    is Some(transform) {
    let off = tree.picture_node(transform.id, "off", uri=picture_drawing_uri)
    changes.append(
      metadata_changes(off, [
        ("x", picture_emu(rect.x)),
        ("y", picture_emu(rect.y)),
      ]),
    )
  } else {
    changes.push(object.transform_change(rect))
  }
  changes
}
