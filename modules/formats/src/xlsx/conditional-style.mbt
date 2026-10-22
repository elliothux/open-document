///|
fn conditional_node(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == spreadsheet_uri &&
    node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(child => child.uri == spreadsheet_uri && children.contains(child.name)) else {
    @failure.reject(
      "protected-content",
      "Unsupported conditional formatting properties: " + node.name,
    )
  }
}

///|
fn conditional_color(
  tree : Tree,
  node : @xml.Node,
  theme : Array[String],
) -> String raise @failure.Failure {
  conditional_node(tree, node, ["rgb", "theme", "indexed", "tint", "auto"], [])
  ignore(flag(node, "auto"))
  read_color(Some(node), theme, "000000")
}

///|
fn conditional_style(
  tree : Tree,
  node : @xml.Node,
  theme : Array[String],
  table~ : Bool = false,
) -> CellFormat raise @failure.Failure {
  conditional_node(tree, node, [], [
    "font", "fill", "border", "numFmt", "alignment",
  ])
  let mut result = CellFormat::new()
  if tree.one(node.id, "font") is Some(font) {
    conditional_node(tree, font, [], [
      "name", "sz", "b", "i", "color", "u", "strike", "vertAlign",
    ])
    let effects = font_decorations(tree, font)
    result = {
      ..result,
      underline: effects.underline,
      strike: effects.strike,
      script: effects.script,
    }
    for child in tree.children.get(font.id).unwrap_or([]) {
      if ["u", "strike", "vertAlign"].contains(child.name) {
        continue
      }
      guard tree.all(font.id, child.name).length() == 1 else {
        @failure.reject("malformed-xlsx", "Duplicate conditional font property")
      }
      if child.name == "color" {
        result = {
          ..result,
          color: Some(conditional_color(tree, child, theme)),
        }
        continue
      }
      conditional_node(tree, child, ["val"], [])
      result = match child.name {
        "name" =>
          { ..result, family: Some(child.attribute("val").unwrap_or("")), }
        "sz" =>
          {
            ..result,
            size: Some(number(child.attribute("val").unwrap_or(""))),
          }
        "b" => { ..result, bold: Some(flag(child, "val", fallback=true)), }
        _ => { ..result, italic: Some(flag(child, "val", fallback=true)), }
      }
    }
  }
  if tree.one(node.id, "fill") is Some(fill) {
    conditional_node(tree, fill, [], ["patternFill"])
    if tree.one(fill.id, "patternFill") is Some(pattern) {
      conditional_node(tree, pattern, ["patternType"], ["fgColor", "bgColor"])
      let kind = pattern.attribute("patternType").unwrap_or("none")
      guard ["none", "solid"].contains(kind) else {
        @failure.reject(
          "protected-content", "Unsupported conditional patterned fill",
        )
      }
      // Differential solid fills use bgColor first (ONLYOFFICE PatternFill.fixForDxf).
      let background = tree.one(pattern.id, "bgColor")
      let foreground = tree.one(pattern.id, "fgColor")
      for color in [background, foreground].iter().filter_map(v => v) {
        ignore(conditional_color(tree, color, theme))
      }
      let color = match background {
        Some(_) => background
        None => foreground
      }
      result = {
        ..result,
        fill: Some(
          if background is Some(_) || kind == "solid" {
            color
            .map(n => conditional_color(tree, n, theme))
            .unwrap_or("ffffff")
          } else {
            ""
          },
        ),
      }
    }
  }
  if tree.one(node.id, "border") is Some(border) {
    conditional_node(tree, border, ["diagonalUp", "diagonalDown", "outline"], [
      "left", "right", "top", "bottom", "diagonal", "vertical", "horizontal",
    ])
    guard !flag(border, "diagonalUp") && !flag(border, "diagonalDown") else {
      @failure.reject(
        "protected-content", "Unsupported conditional diagonal border",
      )
    }
    let edges : Array[CellBorder?] = []
    for
      side in [
        "left", "right", "top", "bottom", "diagonal", "vertical", "horizontal",
      ] {
      let edge = tree
        .one(border.id, side)
        .map(edge => {
          conditional_node(tree, edge, ["style"], ["color"])
          let style = edge.attribute("style").unwrap_or("none")
          guard edge.attribute("style") is Some(_) ||
            tree.one(edge.id, "color") is None else {
            @failure.reject(
              "protected-content", "Conditional border color without a style is unsupported",
            )
          }
          guard ["none", "thin", "medium", "thick", "double"].contains(style) else {
            @failure.reject(
              "protected-content", "Unsupported conditional border style",
            )
          }
          let color = tree
            .one(edge.id, "color")
            .map(n => conditional_color(tree, n, theme))
            .unwrap_or("000000")
          CellBorder::{ style, color, }
        })
      if edges.length() < 4 {
        edges.push(edge)
      } else {
        guard (table && side != "diagonal") ||
          edge.map(e => e.style == "none").unwrap_or(true) else {
          @failure.reject(
            "protected-content", "Unsupported conditional inner border",
          )
        }
      }
    }
    result = {
      ..result,
      left: edges[0],
      right: edges[1],
      top: edges[2],
      bottom: edges[3],
    }
  }
  if tree.one(node.id, "numFmt") is Some(format) {
    conditional_node(tree, format, ["numFmtId", "formatCode"], [])
    result = {
      ..result,
      numberFormat: Some(format.attribute("formatCode").unwrap_or("")),
    }
  }
  if tree.one(node.id, "alignment") is Some(alignment) {
    conditional_node(
      tree,
      alignment,
      ["horizontal", "vertical", "wrapText", "indent", "shrinkToFit"],
      [],
    )
    result = {
      ..result,
      horizontal: alignment.attribute("horizontal"),
      vertical: alignment.attribute("vertical"),
      wrap: alignment
      .attribute("wrapText")
      .map(_ => flag(alignment, "wrapText")),
      indent: alignment.attribute("indent").map(value => natural(value, 250)),
      shrinkToFit: alignment
      .attribute("shrinkToFit")
      .map(_ => flag(alignment, "shrinkToFit")),
    }
  }
  result.validate()
  result
}
