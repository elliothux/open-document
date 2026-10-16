///|
fn clear_names(paragraph : Bool) -> (Array[String], Array[String]) {
  if paragraph {
    (
      ["algn", "marL", "marR", "indent"],
      [
        "lnSpc", "spcBef", "spcAft", "buNone", "buChar", "buClrTx", "buClr", "buFontTx",
        "buFont", "buSzTx", "buSzPct", "buSzPts", "buAutoNum",
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
      let mut name_end = attribute.start - 1
      while name_end > cursor &&
            [9, 10, 13, 32].contains(xml[name_end - 1].to_int()) {
        name_end -= 1
      }
      guard name_end > cursor && xml[name_end - 1] == 61 else {
        @failure.reject(
          "protected-content", "Cannot locate direct formatting attribute",
        )
      }
      name_end -= 1
      while name_end > cursor &&
            [9, 10, 13, 32].contains(xml[name_end - 1].to_int()) {
        name_end -= 1
      }
      let start = name_end - attribute.name.length()
      guard start >= cursor && xml[start:name_end] == attribute.name else {
        @failure.reject(
          "protected-content", "Cannot locate direct formatting name",
        )
      }
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
        if paragraph && child.name == "buClr" {
          check_highlight({ tree: source.tree, node: child, }) catch {
            _ =>
              @failure.reject(
                "protected-content", "Extended bullet color is protected",
              )
          }
        } else if paragraph &&
          !["lnSpc", "spcBef", "spcAft"].contains(child.name) {
          let markup = xml[child.start:child.end]
          guard child.text.trim().is_empty() &&
            source.tree.children.get(child.id).unwrap_or([]).is_empty() &&
            !markup.contains("<!--") &&
            !markup.contains("<?") &&
            child.attributes.all(a => {
              a.uri.is_empty() &&
              (
                (child.name == "buChar" && a.name == "char") ||
                (
                  child.name == "buAutoNum" &&
                  ["type", "startAt"].contains(a.name)
                ) ||
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
