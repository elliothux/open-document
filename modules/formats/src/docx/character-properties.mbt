///|
fn Styles::character_layers(
  self : Styles,
  tree : WordTree,
  paragraph : Int32,
  run : Int32?,
  diagnostics : Array[String],
  style~ : FormatChange[String] = Keep,
) -> Array[(WordTree, Int32, Bool)] raise @failure.Failure {
  let layers = []
  if self.tree is Some(styles) {
    if styles
      .child(0, "docDefaults")
      .bind(id => styles.child(id, "rPrDefault"))
      .bind(id => styles.child(id, "rPr"))
      is Some(id) {
      layers.push((styles, id, false))
    }
    let key = match
      tree.child(paragraph, "pPr").bind(id => tree.value(id, "pStyle")) {
      Some(key) => Some(key)
      None => self.default_paragraph
    }
    if key is Some(key) {
      for style in self.chain(key, diagnostics) {
        if styles.child(style, "rPr") is Some(id) {
          layers.push((styles, id, true))
        }
      }
    }
  }
  if run is Some(run) {
    for layer in self.run_layers(tree, run, diagnostics, style~) {
      layers.push(layer)
    }
  } else if style is Set(key) && self.tree is Some(styles) {
    for id in self.chain(key, diagnostics) {
      if styles.child(id, "rPr") is Some(id) {
        layers.push((styles, id, true))
      }
    }
  }
  layers
}

///|
fn Styles::run_layers(
  self : Styles,
  tree : WordTree,
  run : Int32,
  diagnostics : Array[String],
  style~ : FormatChange[String] = Keep,
) -> Array[(WordTree, Int32, Bool)] raise @failure.Failure {
  let layers = []
  let properties = tree.child(run, "rPr")
  let key = match style {
    Keep => properties.bind(id => tree.value(id, "rStyle"))
    Clear => None
    Set(key) => Some(key)
  }
  if key is Some(key) && self.tree is Some(styles) {
    for style in self.chain(key, diagnostics) {
      if styles.child(style, "rPr") is Some(id) {
        layers.push((styles, id, true))
      }
    }
  }
  if properties is Some(id) {
    layers.push((tree, id, false))
  }
  layers
}

///|
fn Styles::run_character_style(
  self : Styles,
  tree : WordTree,
  run : Int32,
  base : RunStyle,
  diagnostics : Array[String],
) -> RunStyle raise @failure.Failure {
  let mut result = base
  for (tree, id, inherited) in self.run_layers(tree, run, diagnostics) {
    result = run_properties(tree, id, result, self.themes, inherited~)
  }
  result
}

///|
fn Styles::character_style(
  self : Styles,
  tree : WordTree,
  paragraph : Int32,
  run : Int32?,
  diagnostics : Array[String],
  style~ : FormatChange[String] = Keep,
) -> RunStyle raise @failure.Failure {
  let mut result = self.defaults
  for
    (tree, id, inherited) in self.character_layers(
      tree,
      paragraph,
      run,
      diagnostics,
      style~,
    ) {
    result = run_properties(tree, id, result, self.themes, inherited~)
  }
  result
}

///|
fn Styles::character_extras(
  self : Styles,
  tree : WordTree,
  paragraph : Int32,
  run : Int32,
) -> Map[String, String] raise @failure.Failure {
  let result : Map[String, String] = Map([])
  result["bCs.val"] = "0"
  result["iCs.val"] = "0"
  result["cs.val"] = "0"
  result["rtl.val"] = "0"
  for
    (tree, id, inherited) in self.character_layers(tree, paragraph, Some(run), []) {
    tree.check_structure_properties(id)
    for child in tree.children[id] {
      let node = tree.nodes[child]
      if node.name == "bCs" || node.name == "iCs" {
        let key = node.name + ".val"
        let value = tree.character_toggle(
          id,
          node.name,
          result[key] == "1",
          inherited,
        )
        result[key] = if value { "1" } else { "0" }
      } else if ["cs", "rtl"].contains(node.name) {
        result[node.name + ".val"] = if ["0", "false", "off"].contains(
            node.attribute("val", uri=word_uri).unwrap_or("1"),
          ) {
          "0"
        } else {
          "1"
        }
      } else if ["rFonts", "lang", "szCs"].contains(node.name) {
        if node.name == "rFonts" {
          // A higher-level literal font replaces a lower-level theme choice.
          for
            (literal, theme) in [
              ("ascii", "asciiTheme"),
              ("hAnsi", "hAnsiTheme"),
              ("eastAsia", "eastAsiaTheme"),
              ("cs", "cstheme"),
            ] {
            if node.attribute(literal, uri=word_uri) is Some(_) &&
              node.attribute(theme, uri=word_uri) is None {
              result.remove("rFonts." + theme)
            }
          }
        }
        for attribute in node.attributes {
          if node.name != "rFonts" || attribute.name != "ascii" {
            result[node.name + "." + attribute.name] = attribute.value
          }
        }
      }
    }
  }
  result
}

///|
fn property_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value).split("\"").join("&quot;")
}

///|
fn Session::preserve_run_style(
  self : Session,
  tree : WordTree,
  styles : Styles,
  run : Int32,
  paragraph : Int32,
) -> @xml.SourceChange? raise @failure.Failure {
  let original = tree.run_paragraph(run)
  let before = styles.character_style(tree, original, Some(run), [])
  let after = styles.character_style(tree, paragraph, Some(run), [])
  let extras = styles.character_extras(tree, original, run)
  let destination = styles.character_extras(tree, paragraph, run)
  if before == after && extras == destination {
    return None
  }
  // An absent inherited script/language value cannot be cleared with a guessed default.
  for key, _ in destination {
    let direct_font = match key {
      "rFonts.asciiTheme" => true
      "rFonts.hAnsiTheme" => extras.contains("rFonts.hAnsi")
      "rFonts.eastAsiaTheme" => extras.contains("rFonts.eastAsia")
      "rFonts.cstheme" => extras.contains("rFonts.cs")
      _ => false
    }
    guard extras.contains(key) || direct_font else {
      @failure.reject(
        "protected-content",
        "Cannot preserve unspecified inherited character property: " + key,
      )
    }
  }
  let fonts = StringBuilder()
  fonts.write_string(" od:ascii=\"" + property_attribute(before.family) + "\"")
  for
    name in [
      "hAnsi", "eastAsia", "cs", "asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme",
      "hint",
    ] {
    if extras.get("rFonts." + name) is Some(value) {
      fonts.write_string(" od:\{name}=\"" + property_attribute(value) + "\"")
    }
  }
  let fields = StringBuilder()
  fields.write_string("<od:rFonts xmlns:od=\"\{word_uri}\"\{fonts} />")
  for
    (name, value) in [
      ("b", if before.bold { "1" } else { "0" }),
      ("bCs", extras["bCs.val"]),
      ("i", if before.italic { "1" } else { "0" }),
      ("iCs", extras["iCs.val"]),
      ("cs", extras["cs.val"]),
      ("rtl", extras["rtl.val"]),
      ("color", before.color),
      ("sz", (before.size * 2).to_int().to_string()),
      ("u", if before.underline { "single" } else { "none" }),
      ("strike", if before.strike { "1" } else { "0" }),
      ("highlight", before.highlight),
      ("vertAlign", before.vertAlign),
      ("spacing", (before.spacing * 20).round().to_int().to_string()),
    ] {
    fields.write_string(
      "<od:\{name} xmlns:od=\"\{word_uri}\" od:val=\"\{value}\"/>",
    )
  }
  if extras.get("szCs.val") is Some(value) {
    fields.write_string(
      "<od:szCs xmlns:od=\"\{word_uri}\" od:val=\"" +
      property_attribute(value) +
      "\"/>",
    )
  }
  let language = StringBuilder()
  for name in ["val", "eastAsia", "bidi"] {
    if extras.get("lang." + name) is Some(value) {
      language.write_string(" od:\{name}=\"" + property_attribute(value) + "\"")
    }
  }
  if !language.to_string().is_empty() {
    fields.write_string("<od:lang xmlns:od=\"\{word_uri}\"\{language}/>")
  }
  let source = self.document().source()
  let node = tree.nodes[run]
  if tree.child(run, "rPr") is Some(id) {
    let properties = tree.nodes[id]
    let content = StringBuilder()
    let mut offset = properties.opening_end
    for child in tree.children[id] {
      let item = tree.nodes[child]
      content.write_string(source[offset:item.start].to_owned())
      if item.name == "rStyle" {
        content.write_string(source[item.start:item.end].to_owned())
      }
      offset = item.end
    }
    content.write_string(source[offset:properties.closing_start].to_owned())
    content.write_string(fields.to_string())
    return Some(
      if properties.empty {
        {
          node: run,
          offset: properties.opening_end - node.start - 2,
          length: 2,
          xml: ">\{content}</\{properties.qualified}>",
        }
      } else {
        {
          node: run,
          offset: properties.opening_end - node.start,
          length: properties.closing_start - properties.opening_end,
          xml: content.to_string(),
        }
      },
    )
  }
  let content = "<od:rPr xmlns:od=\"\{word_uri}\">\{fields}</od:rPr>"
  Some(
    if node.empty {
      {
        node: run,
        offset: node.opening_end - node.start - 2,
        length: 2,
        xml: ">\{content}</\{node.qualified}>",
      }
    } else {
      {
        node: run,
        offset: node.opening_end - node.start,
        length: 0,
        xml: content,
      }
    },
  )
}
