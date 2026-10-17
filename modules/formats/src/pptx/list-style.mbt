///|
fn normalized_list_size(
  value : TextSpacing,
) -> TextSpacing raise @failure.Failure {
  let factor : Double = if value.unit == "point" { 100 } else { 1000 }
  guard ["point", "percent"].contains(value.unit) &&
    !value.value.is_nan() &&
    !value.value.is_inf() &&
    value.value >= 1 &&
    value.value <= (if value.unit == "point" { 1024 } else { 400 }) else {
    @failure.reject(
      "invalid-operation", "List size must be 1..1024 points or 1..400 percent",
    )
  }
  { unit: value.unit, value: (value.value * factor).round() / factor, }
}

///|
fn check_bullet_property(source : Ref) -> Unit raise @failure.Failure {
  if source.node.name == "buClr" {
    check_highlight(source) catch {
      _ =>
        @failure.reject(
          "protected-content", "Extended bullet color is protected",
        )
    }
    return
  }
  let child = source.node
  let markup = source_xml(source)
  guard child.text.trim().is_empty() &&
    source.tree.children.get(child.id).unwrap_or([]).is_empty() &&
    !markup.contains("<!--") &&
    !markup.contains("<?") &&
    child.attributes.all(a => {
      a.uri.is_empty() &&
      (
        (child.name == "buChar" && a.name == "char") ||
        (child.name == "buAutoNum" && ["type", "startAt"].contains(a.name)) ||
        (["buSzPct", "buSzPts"].contains(child.name) && a.name == "val") ||
        (
          child.name == "buFont" &&
          ["typeface", "pitchFamily", "charset"].contains(a.name)
        )
      )
    }) else {
    @failure.reject(
      "protected-content", "Extended bullet formatting is protected",
    )
  }
}

///|
fn list_style_change(
  properties : Ref?,
  names : Array[String],
  target : String,
  value : String?,
  changes : Map[String, String],
) -> Unit raise @failure.Failure {
  let existing = properties
    .map(p => {
      p.tree.children
      .get(p.node.id)
      .unwrap_or([])
      .filter(n => n.uri == drawing_uri && names.contains(n.name))
    })
    .unwrap_or([])
  guard existing.length() <= 1 else {
    @failure.reject(
      "protected-content", "Ambiguous bullet formatting is protected",
    )
  }
  let mut current : Ref? = None
  for node in existing {
    let source : Ref = { tree: properties.unwrap().tree, node, }
    check_bullet_property(source)
    current = Some(source)
  }
  let attribute = if target == "buFont" { "typeface" } else { "val" }
  if current is Some(source) && source.node.name == target {
    if value is None {
      return
    }
    if target == "buClr" {
      if source.child("srgbClr") is Some(rgb) &&
        rgb.node.attribute("val").map(v => v.to_lower()) == value &&
        rgb.tree.children.get(rgb.node.id).unwrap_or([]).is_empty() {
        return
      }
    } else if source.node.attribute(attribute) == value {
      return
    }
  }
  let markup = if value is Some(value) {
    let value = @xml.escape_text(value).replace_all(old="\"", new="&quot;")
    if target == "buClr" {
      "<a:buClr xmlns:a=\"\{drawing_uri}\"><a:srgbClr val=\"\{value}\"/></a:buClr>"
    } else if target == "buFont" &&
      current is Some(source) &&
      source.node.name == "buFont" {
      frame_opening(source, Map([("typeface", value)])) +
      "</\{source.node.qualified}>"
    } else {
      "<a:\{target} xmlns:a=\"\{drawing_uri}\" \{attribute}=\"\{value}\"/>"
    }
  } else {
    "<a:\{target} xmlns:a=\"\{drawing_uri}\"/>"
  }
  for name in names {
    changes[name] = if name == target { markup } else { "" }
  }
}

///|
fn list_style_changes(
  paragraph : TextParagraph,
  format : ParagraphFormat,
  changes : Map[String, String],
) -> Unit raise @failure.Failure {
  let properties = paragraph.source.child("pPr")
  if format.list_font is Some(font) {
    list_style_change(
      properties,
      ["buFontTx", "buFont"],
      if font is Some(_) {
        "buFont"
      } else {
        "buFontTx"
      },
      font,
      changes,
    )
  }
  if format.list_size is Some(size) {
    let target = match size {
      None => "buSzTx"
      Some({ unit: "point", .. }) => "buSzPts"
      _ => "buSzPct"
    }
    list_style_change(
      properties,
      ["buSzTx", "buSzPct", "buSzPts"],
      target,
      size.map(s => {
        (s.value * (if s.unit == "point" { 100 } else { 1000 }))
        .round()
        .to_int()
        .to_string()
      }),
      changes,
    )
  }
  if format.list_color is Some(color) {
    list_style_change(
      properties,
      ["buClrTx", "buClr"],
      if color is Some(_) {
        "buClr"
      } else {
        "buClrTx"
      },
      color,
      changes,
    )
  }
}
