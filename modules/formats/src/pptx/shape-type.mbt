///|
fn Session::shape_type_reason(self : Session, object : Object) -> String {
  let reason = self.appearance_reason(object)
  if !reason.is_empty() {
    return reason
  }
  try {
    guard object.source.node.name == "sp" &&
      supported_shape(object.preset) &&
      !line_shape(object.preset) &&
      object.geometry is Some(_) else {
      return "Shape type editing requires a supported closed shape"
    }
    let locks = object.source
      .child("nvSpPr", uri=presentation_uri)
      .bind(node => node.child("cNvSpPr", uri=presentation_uri))
      .bind(node => node.child("spLocks"))
    if locks is Some(locks) && flag(locks.node, "noChangeShapeType") {
      return "Shape type editing is locked"
    }
    guard object.source.child("spPr", uri=presentation_uri) is Some(properties) else {
      return "Missing local shape properties"
    }
    if properties.child("prstGeom") is Some(geometry) {
      let source = source_xml(geometry)
      let lists = geometry.tree.children.get(geometry.node.id).unwrap_or([])
      guard !source.contains("<!--") &&
        !source.contains("<?") &&
        geometry.node.attributes.all(a => a.uri.is_empty() && a.name == "prst") &&
        geometry.node.text.trim().is_empty() &&
        lists.length() <= 1 &&
        lists.all(list => {
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
        return "Retained shape geometry is protected"
      }
    }
    if object.body.fit != "none" && !object.paragraphs.is_empty() {
      self.text_frame_reason(object)
    } else {
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::shape_type_changes(
  self : Session,
  preset : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard supported_shape(preset) && !line_shape(preset) else {
    @failure.reject("invalid-operation", "Unsupported closed shape type")
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Select objects to change their shape type",
    )
  }
  let slide = self.current()
  let changes : Array[@xml.SourceChange] = []
  let updated : Map[String, Object] = Map([])
  for id in self.selection.objects {
    let object = slide.object(id)
    let reason = self.shape_type_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    if object.preset == preset {
      continue
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    changes.push(
      paint_child_change(
        properties,
        properties.child("prstGeom").map(value => value.node),
        "<a:prstGeom xmlns:a=\"\{drawing_uri}\" prst=\"\{preset}\"><a:avLst/></a:prstGeom>",
        properties.tree.children
        .get(properties.node.id)
        .unwrap_or([])
        .filter(node => node.name != "xfrm")
        .map(node => node.name),
      ),
    )
    updated[id] = {
      ..object,
      preset,
      adjustments: read_shape_adjustments(None, preset),
    }
  }
  for connector in slide.objects {
    if !connector.connector_targets().any(id => updated.contains(id)) {
      continue
    }
    let (start, end) = connector.connector_ends()
    for (name, point) in [("stCxn", start), ("endCxn", end)] {
      if updated.get(point.target) is Some(target) {
        let sites = target.connection_site_count()
        guard sites > 0 else {
          @failure.reject(
            "protected-content", "Connected targets require supported connection geometry",
          )
        }
        let (x, y) = slide.object(point.target).connection_point(point.site)
        let mut nearest = 0
        let mut distance = 1.0e30
        for site in 0..<sites {
          let (next_x, next_y) = target.connection_point(site)
          let gap = (next_x - x) * (next_x - x) + (next_y - y) * (next_y - y)
          if gap < distance {
            nearest = site
            distance = gap
          }
        }
        if nearest != point.site {
          let reason = self.object_edit_reason(connector, "endpoints")
          guard reason.is_empty() else {
            @failure.reject("protected-content", reason)
          }
          let source = connector.connector_properties().child(name).unwrap()
          changes.push(attribute_change(source, "idx", nearest.to_string()))
        }
      }
    }
  }
  changes
}
