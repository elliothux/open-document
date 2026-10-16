///|
fn check_highlight(source : Ref) -> Unit raise @failure.Failure {
  let tree = source.tree
  let children = tree.children.get(source.node.id).unwrap_or([])
  let xml = source_xml(source)
  guard source.node.attributes.is_empty() &&
    source.node.text.trim().is_empty() &&
    !xml.contains("<!--") &&
    !xml.contains("<?") &&
    children is [color] &&
    color.uri == drawing_uri &&
    ["srgbClr", "sysClr", "schemeClr"].contains(color.name) &&
    color.text.trim().is_empty() &&
    color.attributes.all(a => {
      a.uri.is_empty() &&
      (a.name == "val" || (color.name == "sysClr" && a.name == "lastClr"))
    }) else {
    @failure.reject("unsupported-text", "Extended text highlight is protected")
  }
  let modifiers = tree.children.get(color.id).unwrap_or([])
  guard modifiers.all(n => {
    n.uri == drawing_uri &&
    n.text.trim().is_empty() &&
    n.attributes.length() == 1 &&
    n.attribute("val") is Some(_) &&
    tree.children.get(n.id).unwrap_or([]).is_empty() &&
    (
      ["tint", "shade", "lumMod", "lumOff"].contains(n.name) ||
      (
        color.name == "srgbClr" &&
        modifiers.length() == 1 &&
        n.name == "alpha" &&
        n.attribute("val") == Some("0")
      )
    )
  }) else {
    @failure.reject("unsupported-text", "Unsupported highlight color transform")
  }
}

///|
fn text_highlight(
  theme : Theme,
  sources : Array[Ref],
) -> String raise @failure.Failure {
  for source in sources {
    if source.child("highlight") is Some(highlight) {
      check_highlight(highlight)
      if highlight.child("srgbClr") is Some(rgb) &&
        rgb.child("alpha") is Some(_) {
        ignore(hex_color(rgb.node.attribute("val").unwrap_or("")))
        return ""
      }
      return color(theme, highlight)
    }
  }
  ""
}
