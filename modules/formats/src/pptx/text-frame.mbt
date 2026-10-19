///|
fn Session::text_frame_reason(self : Session, object : Object) -> String {
  if !object.text_reason.is_empty() {
    return object.text_reason
  }
  try {
    let slide = self.slides[self.index(object.source.tree.part)]
    guard slide.read_only.is_empty() else { return slide.read_only }
    guard object.kind == "shape" &&
      (
        !object.parent.is_empty() ||
        object.source.node.parent == shape_tree(slide.tree).id
      ) else {
      return "Text frame editing requires a local shape"
    }
    guard object.source.child("txBody", uri=presentation_uri) is Some(body) else {
      return "Shape has no editable text frame"
    }
    if body.child("bodyPr") is Some(properties) {
      return text_fit_reason(properties)
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn text_fit_reason(properties : Ref) -> String {
  let fits = properties.tree.children
    .get(properties.node.id)
    .unwrap_or([])
    .filter(node => {
      node.uri == drawing_uri &&
      ["noAutofit", "normAutofit", "spAutoFit"].contains(node.name)
    })
  guard fits.length() <= 1 else {
    return "Ambiguous text fit properties are protected"
  }
  for fit in fits {
    let source = source_xml({ tree: properties.tree, node: fit, })
    guard fit.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") &&
      properties.tree.children.get(fit.id).unwrap_or([]).is_empty() &&
      fit.attributes.all(a => {
        a.uri.is_empty() &&
        fit.name == "normAutofit" &&
        ["fontScale", "lnSpcReduction"].contains(a.name)
      }) else {
      return "Unknown text fit properties are protected"
    }
  }
  ""
}

///|
fn frame_attribute_start(
  source : Ref,
  attribute : @xml.Attribute,
) -> Int raise @failure.Failure {
  let xml = source.tree.document.source()
  let mut end = attribute.start - 1
  while end > source.node.start &&
        [9, 10, 13, 32].contains(xml[end - 1].to_int()) {
    end -= 1
  }
  guard end > source.node.start && xml[end - 1] == 61 else {
    @failure.reject(
      "protected-content", "Cannot locate direct formatting attribute",
    )
  }
  end -= 1
  while end > source.node.start &&
        [9, 10, 13, 32].contains(xml[end - 1].to_int()) {
    end -= 1
  }
  let start = end - attribute.name.length()
  guard start >= source.node.start && xml[start:end] == attribute.name else {
    @failure.reject("protected-content", "Cannot locate direct formatting name")
  }
  start
}

///|
fn frame_opening(
  properties : Ref,
  values : Map[String, String],
  removed~ : Array[String] = [],
) -> String raise @failure.Failure {
  let source = source_xml(properties)
  let output = StringBuilder()
  let remaining = values.copy()
  let mut cursor = 0
  for attribute in properties.node.attributes {
    if attribute.uri.is_empty() && removed.contains(attribute.name) {
      output.write_view(
        source[cursor:frame_attribute_start(properties, attribute) -
        properties.node.start],
      )
      cursor = attribute.end + 1 - properties.node.start
      continue
    }
    if attribute.uri.is_empty() && values.get(attribute.name) is Some(value) {
      output.write_string(
        source[cursor:attribute.start - properties.node.start].to_owned(),
      )
      output.write_string(value)
      cursor = attribute.end - properties.node.start
      remaining.remove(attribute.name)
    }
  }
  output.write_string(
    source[cursor:properties.node.opening_end -
    properties.node.start -
    (if properties.node.empty { 2 } else { 1 })].to_owned(),
  )
  for name, value in remaining {
    output.write_string(" \{name}=\"\{value}\"")
  }
  output.to_string() + ">"
}

///|
fn Session::frame_objects(
  self : Session,
  change : ObjectEdit,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard !self.selection.objects.is_empty() else {
    @failure.reject("invalid-operation", "Select a text frame first")
  }
  let values : Map[String, String] = Map([])
  match change {
    TextInsets(left, top, right, bottom) =>
      for
        (key, value) in [
          ("lIns", left),
          ("tIns", top),
          ("rIns", right),
          ("bIns", bottom),
        ] {
        guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400 else {
          @failure.reject(
            "invalid-operation", "Text margins must be within 0 and 14400 points",
          )
        }
        values[key] = (value * 12700).round().to_int64().to_string()
      }
    TextAnchor(anchor) => {
      guard ["t", "ctr", "b"].contains(anchor) else {
        @failure.reject("invalid-operation", "Unknown text anchor")
      }
      values["anchor"] = anchor
    }
    TextWrap(wrap) => values["wrap"] = if wrap { "square" } else { "none" }
    TextFit(fit) => {
      guard ["none", "shrink", "resize"].contains(fit) else {
        @failure.reject("invalid-operation", "Unknown text fit mode")
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown text frame edit")
  }
  let changes : Array[@xml.SourceChange] = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.text_frame_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let body : Body = {
      left: values
      .get("lIns")
      .map(v => number(v, 0, 182880000) / 12700)
      .unwrap_or(object.body.left),
      top: values
      .get("tIns")
      .map(v => number(v, 0, 182880000) / 12700)
      .unwrap_or(object.body.top),
      right: values
      .get("rIns")
      .map(v => number(v, 0, 182880000) / 12700)
      .unwrap_or(object.body.right),
      bottom: values
      .get("bIns")
      .map(v => number(v, 0, 182880000) / 12700)
      .unwrap_or(object.body.bottom),
      anchor: values.get("anchor").unwrap_or(object.body.anchor),
      wrap: if change is TextWrap(wrap) {
        wrap
      } else {
        object.body.wrap
      },
      fit: if change is TextFit(fit) {
        fit
      } else {
        object.body.fit
      },
    }
    let target = { ..object, body, }
    let geometry = if body.fit == "resize" {
      resize_text_frame(target, probe, profile)
    } else {
      object.geometry.unwrap()
    }
    let effective = target.shape_body(geometry)
    guard effective.left + effective.right < geometry.width &&
      effective.top + effective.bottom < geometry.height else {
      @failure.reject("invalid-operation", "Text margins leave no usable frame")
    }
    let (_, scale, diagnostic) = fit_text(target, geometry, probe, profile)
    guard body.fit == "none" || diagnostic.is_empty() else {
      @failure.reject("layout-overflow", diagnostic)
    }
    let tx = object.source.child("txBody", uri=presentation_uri).unwrap()
    let properties = tx.child("bodyPr")
    let fit = properties.bind(p => {
      p.tree.children
      .get(p.node.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == drawing_uri &&
        ["noAutofit", "normAutofit", "spAutoFit"].contains(node.name)
      })
    })
    let replace_fit = body.fit == "shrink" || change is TextFit(_)
    let fit_markup = if body.fit == "shrink" {
      "<a:normAutofit xmlns:a=\"\{drawing_uri}\" fontScale=\"\{(scale * 100000).floor().to_int()}\" lnSpcReduction=\"0\"/>"
    } else if body.fit == "resize" {
      "<a:spAutoFit xmlns:a=\"\{drawing_uri}\"/>"
    } else {
      "<a:noAutofit xmlns:a=\"\{drawing_uri}\"/>"
    }
    let markup = if properties is Some(p) {
      let source = p.tree.document.source()
      let next = p.tree.children
        .get(p.node.id)
        .unwrap_or([])
        .iter()
        .find_first(node => {
          node.uri == drawing_uri &&
          ["scene3d", "sp3d", "flatTx", "extLst"].contains(node.name)
        })
      let inner = if p.node.empty {
        ""
      } else if replace_fit && fit is Some(fit) {
        source[p.node.opening_end:fit.start].to_owned() +
        fit_markup +
        source[fit.end:p.node.closing_start].to_owned()
      } else if replace_fit && fit is None && next is Some(next) {
        source[p.node.opening_end:next.start].to_owned() +
        fit_markup +
        source[next.start:p.node.closing_start].to_owned()
      } else {
        source[p.node.opening_end:p.node.closing_start].to_owned()
      }
      frame_opening(p, values) +
      inner +
      (if replace_fit && fit is None && next is None { fit_markup } else { "" }) +
      "</\{p.node.qualified}>"
    } else {
      let attributes = values
        .iter()
        .map(pair => " \{pair.0}=\"\{pair.1}\"")
        .collect()
        .join("")
      "<a:bodyPr xmlns:a=\"\{drawing_uri}\"\{attributes}>\{if replace_fit { fit_markup } else { "" }}</a:bodyPr>"
    }
    if body.fit == "resize" {
      changes.append(resized_frame_changes(object, geometry))
    }
    if properties is Some(p) && markup == source_xml(p) {
      continue
    }
    changes.push(
      if properties is None && tx.node.empty {
        insertion(tx.node, markup)
      } else {
        {
          node: tx.node.id,
          offset: properties
          .map(p => p.node.start)
          .unwrap_or(tx.node.opening_end) -
          tx.node.start,
          length: properties.map(p => p.node.end - p.node.start).unwrap_or(0),
          xml: markup,
        }
      },
    )
  }
  changes
}
