///|
fn clear_names(paragraph : Bool) -> (Array[String], Array[String]) {
  if paragraph {
    (
      ["algn", "marL", "marR", "indent", "rtl", "defTabSz"],
      [
        "lnSpc", "spcBef", "spcAft", "buNone", "buChar", "buClrTx", "buClr", "buFontTx",
        "buFont", "buSzTx", "buSzPct", "buSzPts", "buAutoNum", "tabLst",
      ],
    )
  } else {
    (
      ["sz", "b", "i", "u", "strike", "baseline"],
      ["noFill", "solidFill", "latin", "ea", "cs", "uLnTx", "uFillTx"],
    )
  }
}

///|
fn has_direct_properties(source : Ref?, paragraph~ : Bool = false) -> Bool {
  guard source is Some(source) else { return false }
  let (attrs, children) = clear_names(paragraph)
  source.node.attributes.any(a => a.uri.is_empty() && attrs.contains(a.name)) ||
  source.tree.children
  .get(source.node.id)
  .unwrap_or([])
  .any(n => n.uri == drawing_uri && children.contains(n.name))
}

///|
fn cleared_properties(
  source : Ref,
  paragraph~ : Bool = false,
) -> String raise @failure.Failure {
  let (attrs, children) = clear_names(paragraph)
  if !paragraph {
    ignore(paint_fill(source))
  }
  let xml = source.tree.document.source()
  let output = StringBuilder()
  let mut cursor = source.node.start
  for attribute in source.node.attributes {
    if attribute.uri.is_empty() && attrs.contains(attribute.name) {
      let start = frame_attribute_start(source, attribute)
      output.write_view(xml[cursor:start])
      cursor = attribute.end + 1
    }
  }
  output.write_view(xml[cursor:source.node.opening_end])
  cursor = source.node.opening_end
  if !source.node.empty {
    for child in source.tree.children.get(source.node.id).unwrap_or([]) {
      output.write_view(xml[cursor:child.start])
      if child.uri == drawing_uri && children.contains(child.name) {
        if paragraph && child.name == "tabLst" {
          guard !source_xml({ tree: source.tree, node: child, }).contains(
              "<!--",
            ) &&
            !source_xml({ tree: source.tree, node: child, }).contains("<?") else {
            @failure.reject(
              "protected-content", "Retained tab source prevents clearing",
            )
          }
        } else if paragraph &&
          !["lnSpc", "spcBef", "spcAft"].contains(child.name) {
          check_bullet_property({ tree: source.tree, node: child, })
        }
        if !paragraph && !["noFill", "solidFill"].contains(child.name) {
          let markup = xml[child.start:child.end]
          guard child.text.trim().is_empty() &&
            source.tree.children.get(child.id).unwrap_or([]).is_empty() &&
            !markup.contains("<!--") &&
            !markup.contains("<?") &&
            child.attributes.all(a => {
              a.uri.is_empty() &&
              ["latin", "ea", "cs"].contains(child.name) &&
              ["typeface", "pitchFamily", "charset"].contains(a.name)
            }) else {
            @failure.reject(
              "protected-content", "Extended character formatting is protected",
            )
          }
        }
      } else {
        output.write_view(xml[child.start:child.end])
      }
      cursor = child.end
    }
    output.write_view(xml[cursor:source.node.end])
  }
  output.to_string()
}
