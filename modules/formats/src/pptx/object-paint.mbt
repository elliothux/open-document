///|
fn paint_fill(properties : Ref) -> @xml.Node? raise @failure.Failure {
  let fills = properties.tree.children
    .get(properties.node.id)
    .unwrap_or([])
    .filter(node => {
      node.uri == drawing_uri &&
      ["noFill", "solidFill", "gradFill", "pattFill", "blipFill", "grpFill"].contains(
        node.name,
      )
    })
  guard fills.length() <= 1 else {
    @failure.reject("protected-content", "Ambiguous shape fill is protected")
  }
  guard fills.get(0) is Some(fill) else { return None }
  let tree = properties.tree
  if fill.name == "blipFill" && properties.node.name == "spPr" {
    ignore(shape_image_source({ tree, node: fill, }))
    return Some(fill)
  }
  if fill.name == "gradFill" && properties.node.name == "spPr" {
    ignore(linear_background_source({ tree, node: fill, }))
    guard [None, Some("1"), Some("true")].contains(
      fill.attribute("rotWithShape"),
    ) else {
      @failure.reject(
        "protected-content", "Fixed-angle shape gradients are protected",
      )
    }
    return Some(fill)
  }
  let source = tree.document.source()[fill.start:fill.end]
  guard ["noFill", "solidFill"].contains(fill.name) &&
    fill.attributes.is_empty() &&
    fill.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown shape fill markup is protected",
    )
  }
  let children = tree.children.get(fill.id).unwrap_or([])
  if fill.name == "noFill" {
    guard children.is_empty() else {
      @failure.reject(
        "protected-content", "Unknown no-fill markup is protected",
      )
    }
  } else {
    guard children is [color] &&
      color.uri == drawing_uri &&
      ["srgbClr", "schemeClr", "sysClr"].contains(color.name) &&
      color.text.trim().is_empty() &&
      color.attributes.all(a => {
        a.uri.is_empty() &&
        (a.name == "val" || (color.name == "sysClr" && a.name == "lastClr"))
      }) else {
      @failure.reject("protected-content", "Unknown shape color is protected")
    }
    guard tree.children
      .get(color.id)
      .unwrap_or([])
      .all(node => {
        node.uri == drawing_uri &&
        ["tint", "shade", "lumMod", "lumOff", "alpha", "alphaMod", "alphaOff"].contains(
          node.name,
        ) &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
        tree.children.get(node.id).unwrap_or([]).is_empty()
      }) else {
      @failure.reject(
        "protected-content", "Unknown shape color transform is protected",
      )
    }
  }
  Some(fill)
}

///|
fn Session::paint_reason(self : Session, object : Object) -> String {
  if !object.read_only.is_empty() {
    return object.read_only
  }
  try {
    let slide = self.slides[self.index(object.source.tree.part)]
    guard slide.read_only.is_empty() else { return slide.read_only }
    guard object.kind == "shape" &&
      object.parent.is_empty() &&
      object.source.node.parent == shape_tree(slide.tree).id else {
      return "Appearance editing requires a local top-level shape"
    }
    guard object.source.child("spPr", uri=presentation_uri) is Some(properties) else {
      return "Missing editable shape properties"
    }
    ignore(paint_fill(properties))
    if properties.child("ln") is Some(line) {
      ignore(paint_fill(line))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn paint_markup(value : String?, opacity~ : Double = 1) -> String {
  let alpha = if opacity == 1 {
    ""
  } else {
    "<a:alpha val=\"\{(opacity * 100000).round().to_int()}\"/>"
  }
  match value {
    None => "<a:noFill xmlns:a=\"\{drawing_uri}\"/>"
    Some(color) =>
      if alpha.is_empty() {
        "<a:solidFill xmlns:a=\"\{drawing_uri}\"><a:srgbClr val=\"\{color.to_lower()}\"/></a:solidFill>"
      } else {
        "<a:solidFill xmlns:a=\"\{drawing_uri}\"><a:srgbClr val=\"\{color.to_lower()}\">\{alpha}</a:srgbClr></a:solidFill>"
      }
  }
}

///|
fn same_paint(
  properties : Ref,
  value : String?,
  opacity~ : Double = 1,
) -> Bool raise @failure.Failure {
  guard paint_fill(properties) is Some(fill) else { return false }
  if value is None {
    return fill.name == "noFill"
  }
  let children = properties.tree.children.get(fill.id).unwrap_or([])
  value is Some(value) &&
  children is [color] &&
  color.name == "srgbClr" &&
  color.attribute("val").map(c => c.to_lower()) == Some(value.to_lower()) &&
  (match properties.tree.children.get(color.id).unwrap_or([]) {
    [] => opacity == 1
    [alpha] =>
      alpha.name == "alpha" &&
      alpha.attribute("val") ==
      Some((opacity * 100000).round().to_int().to_string())
    _ => false
  })
}

///|
fn paint_child_change(
  properties : Ref,
  child : @xml.Node?,
  markup : String,
  after : Array[String],
) -> @xml.SourceChange {
  let parent = properties.node
  if child is Some(child) {
    {
      node: parent.id,
      offset: child.start - parent.start,
      length: child.end - child.start,
      xml: markup,
    }
  } else if properties.tree.children
    .get(parent.id)
    .unwrap_or([])
    .iter()
    .find_first(node => node.uri == drawing_uri && after.contains(node.name))
    is Some(next) {
    {
      node: parent.id,
      offset: next.start - parent.start,
      length: 0,
      xml: markup,
    }
  } else {
    insertion(parent, markup)
  }
}

///|
fn Session::paint_objects(
  self : Session,
  change : ObjectEdit,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let (color, width) = match change {
    Fill(color) => (color, None)
    Stroke(color, width) => {
      guard !width.is_nan() && !width.is_inf() && width >= 0.1 && width <= 1000 else {
        @failure.reject(
          "invalid-operation", "Line width must be within 0.1 and 1000 points",
        )
      }
      (color, Some((width * 12700).round().to_int64().to_string()))
    }
    _ => @failure.reject("invalid-operation", "Unknown appearance edit")
  }
  if color is Some(color) {
    guard color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "invalid-operation", "Shape color requires six hexadecimal digits or null",
      )
    }
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Appearance editing requires selected objects",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.paint_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let opacity = if width is Some(_) {
      object.stroke_alpha
    } else {
      object.fill_alpha
    }
    let markup = paint_markup(color, opacity~)
    if width is Some(width) {
      let line = properties.child("ln")
      if line is Some(line) {
        let changed_width = line.node.attribute("w").unwrap_or("12700") != width
        let changed_color = !same_paint(line, color, opacity~)
        if !changed_width && !changed_color {
          continue
        }
        if line.node.empty {
          let attribute = attribute_change(line, "w", width)
          let source = source_xml(line)
          let opening = source[:attribute.offset].to_owned() +
            attribute.xml +
            source[attribute.offset + attribute.length:source.length() - 2].to_owned()
          changes.push(
            paint_child_change(
              properties,
              Some(line.node),
              opening + ">" + markup + "</\{line.node.qualified}>",
              [],
            ),
          )
        } else {
          if changed_width {
            changes.push(attribute_change(line, "w", width))
          }
          if changed_color {
            changes.push(
              paint_child_change(line, paint_fill(line), markup, [
                "prstDash", "custDash", "round", "bevel", "miter", "headEnd", "tailEnd",
                "extLst",
              ]),
            )
          }
        }
      } else {
        changes.push(
          paint_child_change(
            properties,
            None,
            "<a:ln xmlns:a=\"\{drawing_uri}\" w=\"\{width}\">\{markup}</a:ln>",
            ["effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
          ),
        )
      }
    } else {
      let use_background = flag(object.source.node, "useBgFill")
      if same_paint(properties, color, opacity~) && !use_background {
        continue
      }
      changes.push(
        paint_child_change(properties, paint_fill(properties), markup, [
          "ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst",
        ]),
      )
      if use_background {
        changes.push(attribute_change(object.source, "useBgFill", "0"))
      }
    }
  }
  changes
}
