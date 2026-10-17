///|
fn solid_fill_source(sources : Array[Ref]) -> Ref? {
  for item in sources {
    for node in item.tree.children.get(item.node.id).unwrap_or([]) {
      if node.uri == drawing_uri {
        if node.name == "solidFill" {
          return Some({ tree: item.tree, node, })
        }
        if node.name == "noFill" {
          return None
        }
      }
    }
  }
  None
}

///|
fn Session::paint_opacity_reason(
  self : Session,
  object : Object,
  stroke : Bool,
) -> String {
  let reason = self.paint_reason(object)
  if !reason.is_empty() {
    return reason
  }
  if (if stroke { object.stroke_source } else { object.fill_source }) is None {
    return "Opacity editing requires a solid or image fill, or a solid border"
  }
  if !stroke &&
    object.fill_source is Some((fill, _)) &&
    fill.node.name == "blipFill" &&
    fill.tree.part != object.source.tree.part {
    return "Inherited image fill opacity requires a local override"
  }
  ""
}

///|
fn opacity_color_markup(
  source : Ref,
  placeholder : Ref?,
  amount : Int,
) -> String raise @failure.Failure {
  let tree = source.tree
  let colors = tree.children.get(source.node.id).unwrap_or([])
  guard colors is [node] else {
    @failure.reject("protected-content", "Unknown solid fill color")
  }
  let color : Ref = { tree, node, }
  let sources = if node.name == "schemeClr" &&
    node.attribute("val") == Some("phClr") {
    guard placeholder is Some(reference) &&
      reference.tree.children.get(reference.node.id).unwrap_or([]) is [base] else {
      @failure.reject("protected-content", "Missing placeholder color")
    }
    [{ tree: reference.tree, node: base, }, color]
  } else {
    [color]
  }
  let first = sources[0]
  guard sources.all(item => {
    item.node.attributes.all(a => {
      a.uri.is_empty() &&
      (a.name == "val" || (item.node.name == "sysClr" && a.name == "lastClr"))
    }) &&
    !source_xml(item).contains("<!--") &&
    !source_xml(item).contains("<?")
  }) else {
    @failure.reject(
      "protected-content", "Unknown inherited color markup is protected",
    )
  }
  let attrs = first.node.attributes
    .map(a => " \{a.name}=\"\{xml_attribute(a.value)}\"")
    .join("")
  let fields : Array[String] = []
  for item in sources {
    for modifier in item.tree.children.get(item.node.id).unwrap_or([]) {
      if ["alpha", "alphaMod", "alphaOff"].contains(modifier.name) {
        continue
      }
      fields.push(item.tree.standalone_markup(item.tree.document, modifier.id))
    }
  }
  fields.push("<a:alpha val=\"\{amount}\"/>")
  "<a:solidFill xmlns:a=\"\{drawing_uri}\"><a:\{first.node.name}\{attrs}>\{fields.join("")}</a:\{first.node.name}></a:solidFill>"
}

///|
fn Session::opacity_objects(
  self : Session,
  value : Double,
  stroke : Bool,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard value >= 0 && value <= 1 && !value.is_nan() && !value.is_inf() else {
    @failure.reject(
      "invalid-operation", "Shape opacity must be between zero and one",
    )
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Shape opacity editing requires selected objects",
    )
  }
  let amount = (value * 100000).round().to_int()
  let changes = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.paint_opacity_reason(object, stroke)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let alpha = if stroke { object.stroke_alpha } else { object.fill_alpha }
    if (alpha * 100000).round().to_int() == amount {
      continue
    }
    let (source, placeholder) = (if stroke {
      object.stroke_source
    } else {
      object.fill_source
    }).unwrap()
    guard !source_xml(source).contains("<!--") &&
      !source_xml(source).contains("<?") else {
      @failure.reject("protected-content", "Retained color markup is protected")
    }
    let markup = if !stroke && source.node.name == "blipFill" {
      image_fill_opacity_markup(source, amount)
    } else {
      opacity_color_markup(source, placeholder, amount)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    if stroke {
      if properties.child("ln") is Some(line) {
        changes.push(
          paint_child_change(line, paint_fill(line), markup, [
            "prstDash", "custDash", "round", "bevel", "miter", "headEnd", "tailEnd",
            "extLst",
          ]),
        )
      } else {
        changes.push(
          paint_child_change(
            properties,
            None,
            "<a:ln xmlns:a=\"\{drawing_uri}\">\{markup}</a:ln>",
            ["effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
          ),
        )
      }
    } else {
      changes.push(
        paint_child_change(properties, paint_fill(properties), markup, [
          "ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst",
        ]),
      )
    }
  }
  changes
}
