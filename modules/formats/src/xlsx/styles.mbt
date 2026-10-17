///|
priv struct CellStyle {
  font : String
  size : Double
  color : String
  fill : String
  borders : Array[(String, Double)]
  horizontal : String
  vertical : String
  wrap : Bool
  format : String
  diagnostic : String
  bar : ConditionalBar?
} derive(Eq)

///|
fn default_style() -> CellStyle {
  {
    font: "Calibri",
    size: 11,
    color: "000000",
    fill: "",
    borders: Array::make(4, ("", 0.0)),
    horizontal: "general",
    vertical: "bottom",
    wrap: false,
    format: "General",
    diagnostic: "",
    bar: None,
  }
}

///|
fn flag(
  node : @xml.Node,
  name : String,
  fallback~ : Bool = false,
) -> Bool raise @failure.Failure {
  match node.attribute(name) {
    None => fallback
    Some("1" | "true") => true
    Some("0" | "false") => false
    _ => @failure.reject("malformed-xlsx", "Invalid boolean attribute")
  }
}

///|
fn color_hex(value : String) -> String raise @failure.Failure {
  let value = if value.length() == 8 { value[2:].to_owned() } else { value }
  guard value.length() == 6 &&
    value
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }) else {
    @failure.reject("malformed-xlsx", "Invalid style color")
  }
  value.to_lower()
}

///|
fn read_color(
  node : @xml.Node?,
  theme : Array[String],
  fallback : String,
) -> String raise @failure.Failure {
  guard node is Some(node) else { return fallback }
  let color = if node.attribute("rgb") is Some(rgb) {
    color_hex(rgb)
  } else if node.attribute("theme") is Some(index) {
    let i = natural(index, 11)
    theme[i]
  } else if node.attribute("indexed") is Some(index) {
    let i = natural(index, 65)
    let indexed = [
      "000000", "ffffff", "ff0000", "00ff00", "0000ff", "ffff00", "ff00ff", "00ffff",
      "000000", "ffffff", "ff0000", "00ff00", "0000ff", "ffff00", "ff00ff", "00ffff",
      "800000", "008000", "000080", "808000", "800080", "008080", "c0c0c0", "808080",
      "9999ff", "993366", "ffffcc", "ccffff", "660066", "ff8080", "0066cc", "ccccff",
      "000080", "ff00ff", "ffff00", "00ffff", "800080", "800000", "008080", "0000ff",
      "00ccff", "ccffff", "ccffcc", "ffff99", "99ccff", "ff99cc", "cc99ff", "ffcc99",
      "3366ff", "33cccc", "99cc00", "ffcc00", "ff9900", "ff6600", "666699", "969696",
      "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333",
    ]
    if i < indexed.length() {
      indexed[i]
    } else {
      fallback
    }
  } else {
    fallback
  }
  let tint = node.attribute("tint").map(number).unwrap_or(0)
  guard tint >= -1 && tint <= 1 else {
    @failure.reject("malformed-xlsx", "Invalid color tint")
  }
  if tint == 0 {
    return color
  }
  let result = StringBuilder()
  let digits = "0123456789abcdef"
  for offset in [0, 2, 4] {
    let channel = @string.parse_int(color[offset:offset + 2], base=16) catch {
      _ => 0
    }
    let value = (if tint < 0 {
        channel.to_double() * (1 + tint)
      } else {
        channel.to_double() * (1 - tint) + 255 * tint
      })
      .round()
      .to_int()
    result.write_char(digits.get_char(value / 16).unwrap())
    result.write_char(digits.get_char(value % 16).unwrap())
  }
  result.to_string()
}

///|
fn read_styles(
  document : @xml.Document,
  theme : Array[String],
) -> Array[CellStyle] raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("styleSheet")
  let children = fn(name) raise @failure.Failure {
    tree
    .one(root.id, name)
    .map(node => {
      tree.all(
        node.id,
        if name == "cellXfs" {
          "xf"
        } else if name == "fonts" {
          "font"
        } else if name == "fills" {
          "fill"
        } else {
          "border"
        },
      )
    })
    .unwrap_or([])
  }
  let fonts = children("fonts")
  let fills = children("fills")
  let borders = children("borders")
  let formats : Map[Int, String] = Map([])
  for
    (id, code) in [
      (0, "General"),
      (1, "0"),
      (2, "0.00"),
      (3, "#,##0"),
      (4, "#,##0.00"),
      (9, "0%"),
      (10, "0.00%"),
      (14, "mm-dd-yy"),
      (15, "d-mmm-yy"),
      (16, "d-mmm"),
      (17, "mmm-yy"),
      (18, "h:mm AM/PM"),
      (19, "h:mm:ss AM/PM"),
      (20, "h:mm"),
      (21, "hh:mm:ss"),
      (22, "m/d/yy h:mm"),
      (49, "@"),
    ] {
    formats[id] = code
  }
  if tree.one(root.id, "numFmts") is Some(container) {
    for node in tree.all(container.id, "numFmt") {
      formats[natural(node.attribute("numFmtId").unwrap_or(""), 65535)] = node
        .attribute("formatCode")
        .unwrap_or("")
    }
  }
  let result : Array[CellStyle] = []
  for xf in children("cellXfs") {
    guard result.length() < 4096 else {
      @failure.reject("limit-exceeded", "Style count exceeds budget")
    }
    let mut style = default_style()
    let font_id = natural(xf.attribute("fontId").unwrap_or("0"), 4095)
    let fill_id = natural(xf.attribute("fillId").unwrap_or("0"), 4095)
    let border_id = natural(xf.attribute("borderId").unwrap_or("0"), 4095)
    guard font_id < fonts.length() &&
      fill_id < fills.length() &&
      border_id < borders.length() else {
      @failure.reject(
        "malformed-xlsx", "Style component index is out of bounds",
      )
    }
    let font = fonts[font_id]
    if tree.children
      .get(font.id)
      .unwrap_or([])
      .any(node => {
        !["name", "sz", "b", "i", "color", "family", "charset", "scheme"].contains(
          node.name,
        )
      }) {
      style = { ..style, diagnostic: "Unsupported font decoration", }
    }
    let toggle = fn(name) raise @failure.Failure {
      tree
      .one(font.id, name)
      .map(node => flag(node, "val", fallback=true))
      .unwrap_or(false)
    }
    let family = tree
      .one(font.id, "name")
      .bind(node => node.attribute("val"))
      .unwrap_or("Calibri")
    let size = tree
      .one(font.id, "sz")
      .bind(node => node.attribute("val"))
      .map(number)
      .unwrap_or(11)
    guard !family.is_empty() &&
      family.length() <= 256 &&
      size >= 1 &&
      size <= 409 else {
      @failure.reject("malformed-xlsx", "Invalid cell font")
    }
    style = {
      ..style,
      font: family +
      (if toggle("b") { "|bold" } else { "" }) +
      (if toggle("i") { "|italic" } else { "" }),
      size,
      color: read_color(tree.one(font.id, "color"), theme, "000000"),
    }
    if tree.one(fills[fill_id].id, "patternFill") is Some(pattern) {
      let kind = pattern.attribute("patternType").unwrap_or("none")
      if kind == "solid" {
        style = {
          ..style,
          fill: read_color(tree.one(pattern.id, "fgColor"), theme, "ffffff"),
        }
      } else if kind != "none" {
        style = { ..style, diagnostic: "Unsupported patterned fill", }
      }
    } else if tree.one(fills[fill_id].id, "gradientFill") is Some(_) {
      style = { ..style, diagnostic: "Unsupported gradient fill", }
    }
    let edges : Array[(String, Double)] = []
    if flag(borders[border_id], "diagonalUp") ||
      flag(borders[border_id], "diagonalDown") {
      style = { ..style, diagnostic: "Unsupported diagonal border", }
    }
    for side in ["left", "right", "top", "bottom"] {
      let edge = tree.one(borders[border_id].id, side)
      let kind = edge.bind(node => node.attribute("style")).unwrap_or("none")
      let width = match kind {
        "thin" => 0.75
        "medium" => 1.5
        "thick" => 2.25
        "none" => 0.0
        _ => {
          style = { ..style, diagnostic: "Unsupported border style", }
          0.0
        }
      }
      edges.push(
        (
          if width == 0 {
            ""
          } else {
            read_color(
              edge.bind(node => tree.one(node.id, "color")),
              theme,
              "000000",
            )
          },
          width,
        ),
      )
    }
    style = { ..style, borders: edges, }
    if tree.one(xf.id, "alignment") is Some(alignment) {
      let horizontal = alignment.attribute("horizontal").unwrap_or("general")
      let vertical = alignment.attribute("vertical").unwrap_or("bottom")
      if !["general", "left", "center", "right"].contains(horizontal) ||
        !["top", "center", "bottom"].contains(vertical) ||
        alignment.attribute("textRotation").unwrap_or("0") != "0" ||
        alignment.attribute("indent").unwrap_or("0") != "0" ||
        flag(alignment, "shrinkToFit") {
        style = { ..style, diagnostic: "Unsupported text alignment", }
      }
      style = {
        ..style,
        horizontal,
        vertical,
        wrap: flag(alignment, "wrapText"),
      }
    }
    let format_id = natural(xf.attribute("numFmtId").unwrap_or("0"), 65535)
    style = {
      ..style,
      format: formats.get(format_id).unwrap_or("unsupported:\{format_id}"),
    }
    if !supported_format(style.format) {
      style = {
        ..style,
        diagnostic: "Unsupported number format: " + style.format,
      }
    }
    for component in [font, fills[fill_id], borders[border_id]] {
      for child in tree.children.get(component.id).unwrap_or([]) {
        for color in [child] + tree.children.get(child.id).unwrap_or([]) {
          if color.attribute("tint").map(number).unwrap_or(0) != 0 {
            style = { ..style, diagnostic: "Unsupported color tint", }
          }
        }
      }
    }
    result.push(style)
  }
  guard !result.is_empty() else {
    @failure.reject("malformed-xlsx", "Missing cell formats")
  }
  result
}
