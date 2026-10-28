///|
pub(all) struct TextFormat {
  font : String?
  size : Double?
  spacing : Double?
  bold : Bool?
  italic : Bool?
  color : String?
  underline : Bool?
  strike : Bool?
  highlight : String?
  script : String?
}

///|
pub fn TextFormat::new(
  font? : String,
  size? : Double,
  spacing? : Double,
  bold? : Bool,
  italic? : Bool,
  color? : String,
  underline? : Bool,
  strike? : Bool,
  highlight? : String,
  script? : String,
) -> TextFormat {
  {
    font,
    size,
    spacing,
    bold,
    italic,
    color,
    underline,
    strike,
    highlight,
    script,
  }
}

///|
fn TextFormat::normalized(
  self : TextFormat,
) -> TextFormat raise @failure.Failure {
  guard self.font is Some(_) ||
    self.size is Some(_) ||
    self.spacing is Some(_) ||
    self.bold is Some(_) ||
    self.italic is Some(_) ||
    self.color is Some(_) ||
    self.underline is Some(_) ||
    self.strike is Some(_) ||
    self.highlight is Some(_) ||
    self.script is Some(_) else {
    @failure.reject("invalid-operation", "Specify a text format property")
  }
  if self.font is Some(font) {
    guard !font.trim().is_empty() &&
      font.length() <= 200 &&
      !font.contains("|") &&
      !font.has_prefix("+") &&
      @xml.valid_text(font) &&
      !font.contains("\n") &&
      !font.contains("\r") else {
      @failure.reject("invalid-operation", "Invalid text font family")
    }
  }
  if self.size is Some(size) {
    guard !size.is_nan() && !size.is_inf() && size >= 1 && size <= 1024 else {
      @failure.reject("invalid-operation", "Text size must be 1..1024 points")
    }
  }
  if self.spacing is Some(spacing) {
    guard !spacing.is_nan() && !spacing.is_inf() && spacing.abs() <= 1584 else {
      @failure.reject(
        "invalid-operation", "Text spacing must be within -1584 and 1584 points",
      )
    }
  }
  if self.script is Some(script) {
    guard ["baseline", "superscript", "subscript"].contains(script) else {
      @failure.reject("invalid-operation", "Invalid text script")
    }
  }
  for (color, clear) in [(self.color, false), (self.highlight, true)] {
    if color is Some(color) && !(clear && color.is_empty()) {
      guard color.length() == 6 &&
        color
        .iter()
        .all(c => {
          (c >= '0' && c <= '9') ||
          (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F')
        }) else {
        @failure.reject(
          "invalid-operation", "Text color must be six RGB hex digits",
        )
      }
    }
  }
  {
    ..self,
    size: self.size.map(v => (v * 100).round() / 100),
    spacing: self.spacing.map(v => (v * 100).round() / 100),
    color: self.color.map(v => v.to_lower()),
    highlight: self.highlight.map(v => v.to_lower()),
  }
}

///|
fn TextFormat::matches(self : TextFormat, style : @layout.TextStyle) -> Bool {
  let font = style.font.split("|").map(v => v.to_owned()).to_array()
  self.font.map(v => v == font[0]).unwrap_or(true) &&
  self.size.map(v => v == style.size).unwrap_or(true) &&
  self.spacing.map(v => v == style.spacing).unwrap_or(true) &&
  self.bold.map(v => v == font.contains("bold")).unwrap_or(true) &&
  self.italic.map(v => v == font.contains("italic")).unwrap_or(true) &&
  self.color.map(v => v == style.color.to_lower()).unwrap_or(true) &&
  self.underline.map(v => v == style.underline).unwrap_or(true) &&
  self.strike.map(v => v == style.strike).unwrap_or(true) &&
  self.highlight.map(v => v == style.highlight.to_lower()).unwrap_or(true) &&
  self.script.map(v => v == style.script).unwrap_or(true)
}

///|
fn formatted_properties(
  properties : Ref?,
  name : String,
  format : TextFormat?,
  hyperlink~ : String? = None,
) -> String raise @failure.Failure {
  if format is None && hyperlink is None {
    return if properties is Some(properties) {
      cleared_properties(properties)
    } else {
      "<a:\{name} xmlns:a=\"\{drawing_uri}\"/>"
    }
  }
  let format = format.unwrap_or(TextFormat::new())
  let attrs : Map[String, String] = Map([])
  if format.size is Some(value) {
    attrs["sz"] = (value * 100).round().to_int().to_string()
  }
  if format.spacing is Some(value) {
    attrs["spc"] = (value * 100).round().to_int().to_string()
  }
  if format.bold is Some(value) {
    attrs["b"] = if value { "1" } else { "0" }
  }
  if format.italic is Some(value) {
    attrs["i"] = if value { "1" } else { "0" }
  }
  if format.underline is Some(value) {
    attrs["u"] = if value { "sng" } else { "none" }
  }
  if format.strike is Some(value) {
    attrs["strike"] = if value { "sngStrike" } else { "noStrike" }
  }
  if format.script is Some(value) {
    attrs["baseline"] = match value {
      "superscript" => "30000"
      "subscript" => "-25000"
      _ => "0"
    }
  }
  let replacements : Map[String, String] = Map([])
  if hyperlink is Some(markup) {
    replacements["hlinkClick"] = markup
  }
  if format.highlight is Some(value) {
    if properties.bind(p => p.child("highlight")) is Some(existing) {
      check_highlight(existing)
    }
    let color = if value.is_empty() {
      "<a:srgbClr val=\"000000\"><a:alpha val=\"0\"/></a:srgbClr>"
    } else {
      "<a:srgbClr val=\"\{value}\"/>"
    }
    replacements["highlight"] = "<a:highlight xmlns:a=\"\{drawing_uri}\">\{color}</a:highlight>"
  }
  if format.color is Some(value) {
    let fill = properties.bind(paint_fill)
    replacements[fill.map(n => n.name).unwrap_or("solidFill")] = "<a:solidFill xmlns:a=\"\{drawing_uri}\"><a:srgbClr val=\"\{value}\"/></a:solidFill>"
  }
  if format.font is Some(value) {
    let value = @xml.escape_text(value).replace_all(old="\"", new="&quot;")
    for kind in ["latin", "ea", "cs"] {
      replacements[kind] = if properties.bind(p => p.child(kind)) is Some(font) {
        frame_opening(font, Map([("typeface", value)])) +
        (if font.node.empty {
          ""
        } else {
          font.tree.document.source()[font.node.opening_end:font.node.closing_start].to_owned()
        }) +
        "</\{font.node.qualified}>"
      } else {
        "<a:\{kind} xmlns:a=\"\{drawing_uri}\" typeface=\"\{value}\"/>"
      }
    }
  }
  let order = [
    "ln", "noFill", "solidFill", "gradFill", "blipFill", "pattFill", "grpFill", "effectLst",
    "effectDag", "highlight", "uLnTx", "uLn", "uFillTx", "uFill", "latin", "ea",
    "cs", "sym", "hlinkClick", "hlinkMouseOver", "rtl", "extLst",
  ]
  let additions = StringBuilder()
  let output = StringBuilder()
  let mut qualified = "a:" + name
  if properties is Some(properties) {
    qualified = properties.node.qualified
    output.write_string(frame_opening(properties, attrs))
    let xml = properties.tree.document.source()
    let mut cursor = properties.node.opening_end
    if !properties.node.empty {
      for node in properties.tree.children.get(properties.node.id).unwrap_or([]) {
        output.write_view(xml[cursor:node.start])
        let index = order.search(node.name).unwrap_or(order.length())
        for kind in order[:index] {
          if replacements.get(kind) is Some(markup) {
            output.write_string(markup)
            replacements.remove(kind) |> ignore
          }
        }
        if replacements.get(node.name) is Some(markup) &&
          node.uri == drawing_uri {
          output.write_string(markup)
          replacements.remove(node.name) |> ignore
        } else {
          output.write_view(xml[node.start:node.end])
        }
        cursor = node.end
      }
      output.write_view(xml[cursor:properties.node.closing_start])
    }
  } else {
    for key, value in attrs {
      additions.write_string(" \{key}=\"\{value}\"")
    }
    output.write_string("<\{qualified} xmlns:a=\"\{drawing_uri}\"\{additions}>")
  }
  for key in order {
    if replacements.get(key) is Some(markup) {
      output.write_string(markup)
    }
  }
  output.write_string("</\{qualified}>")
  output.to_string()
}

///|
fn format_run(
  run : TextRun,
  start : Int32,
  end : Int32,
  format : TextFormat?,
  clear~ : Bool = false,
  hyperlink~ : String? = None,
) -> String raise @failure.Failure {
  let source = run.source.unwrap()
  if format is None &&
    hyperlink is None &&
    !clear &&
    start == 0 &&
    end == run.text.length() {
    return source_xml(source)
  }
  let output = StringBuilder()
  let xml = source.tree.document.source()
  let marker = source.node.name == "br" && start == end
  let qualified = if marker {
    source.node.qualified[:source.node.qualified.length() - 2].to_owned() + "r"
  } else {
    source.node.qualified
  }
  output.write_string("<" + qualified)
  output.write_view(
    xml[source.node.start + 1 + source.node.qualified.length():source.node.opening_end -
    (if source.node.empty { 2 } else { 1 })],
  )
  output.write_string(">")
  let properties = source.child("rPr")
  let mut cursor = source.node.opening_end
  if !source.node.empty {
    for node in source.tree.children.get(source.node.id).unwrap_or([]) {
      output.write_view(xml[cursor:node.start])
      if node.name == "rPr" &&
        node.uri == drawing_uri &&
        (format is Some(_) || clear || hyperlink is Some(_)) {
        output.write_string(
          formatted_properties(
            Some({ tree: source.tree, node, }),
            "rPr",
            format,
            hyperlink~,
          ),
        )
      } else if node.name == "t" && node.uri == drawing_uri {
        if properties is None &&
          (format is Some(_) || clear || hyperlink is Some(_)) {
          output.write_string(
            formatted_properties(None, "rPr", format, hyperlink~),
          )
        }
        output.write_view(
          xml[node.start:node.opening_end - (if node.empty { 2 } else { 1 })],
        )
        output.write_string(
          ">" +
          @xml.escape_text(run.text[start:end].to_owned()) +
          "</\{node.qualified}>",
        )
      } else {
        output.write_view(xml[node.start:node.end])
      }
      cursor = node.end
    }
    output.write_view(xml[cursor:source.node.closing_start])
  }
  if source.node.name == "br" &&
    properties is None &&
    (format is Some(_) || clear || hyperlink is Some(_)) {
    output.write_string(formatted_properties(None, "rPr", format, hyperlink~))
  }
  if marker {
    output.write_string("<a:t xmlns:a=\"\{drawing_uri}\"/>")
  }
  output.write_string("</\{qualified}>")
  output.to_string()
}
