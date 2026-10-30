///|
let table_shading_attributes : Array[String] = [
  "val", "color", "fill", "themeColor", "themeTint", "themeShade", "themeFill", "themeFillTint",
  "themeFillShade",
]

///|
fn WordTree::table_shading(
  self : WordTree,
  properties : Int32,
  themes : Map[String, String]?,
) -> String? raise @failure.Failure {
  let sources = self.table_children(properties, "shd")
  guard sources.length() <= 1 else {
    @failure.reject("unsupported-layout", "Duplicate table shading")
  }
  guard sources.get(0) is Some(id) else { return None }
  let node = self.nodes[id]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && table_shading_attributes.contains(a.name)
    }) &&
    ["clear", "nil", "pct25"].contains(
      node.attribute("val", uri=word_uri).unwrap_or("clear"),
    ) else {
    @failure.reject("unsupported-layout", "Unsupported table shading")
  }
  ignore(theme_color_reference(node))
  for field in ["color", "fill"] {
    let value = node.attribute(field, uri=word_uri).unwrap_or("auto")
    guard value == "auto" ||
      (value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit())) else {
      @failure.reject("invalid-table", "Invalid table shading color")
    }
  }
  let fallback = node.attribute("fill", uri=word_uri).unwrap_or("auto")
  let color = match themes {
    Some(values) => theme_node_color(node, fallback, values, fill=true)
    None => {
      ignore(theme_color_reference(node, fill=true))
      fallback
    }
  }
  let color = if node.attribute("val", uri=word_uri) == Some("pct25") {
    let foreground = match themes {
      Some(values) =>
        theme_node_color(
          node,
          node.attribute("color", uri=word_uri).unwrap_or("auto"),
          values,
        )
      None => node.attribute("color", uri=word_uri).unwrap_or("auto")
    }
    let foreground = if foreground == "auto" { "000000" } else { foreground }
    let background = if color == "auto" { "ffffff" } else { color }
    let output = StringBuilder()
    for offset in [0, 2, 4] {
      let a = @string.parse_int(foreground[offset:offset + 2], base=16) catch {
        _ => @failure.reject("invalid-table", "Invalid shading foreground")
      }
      let b = @string.parse_int(background[offset:offset + 2], base=16) catch {
        _ => @failure.reject("invalid-table", "Invalid shading background")
      }
      output.write_string(
        ((a + b * 3) / 4).to_string(radix=16).pad_start(2, '0'),
      )
    }
    output.to_string()
  } else {
    color
  }
  Some(
    if color == "auto" || node.attribute("val", uri=word_uri) == Some("nil") {
      ""
    } else {
      color.to_lower()
    },
  )
}

///|
fn WordTree::table_fill_patch(
  self : WordTree,
  cell : Int32,
  attributes : Map[String, String?],
  theme : String?,
  themes : Map[String, String],
) -> Map[String, String?] raise @failure.Failure {
  let original = self
    .child(cell, "tcPr")
    .bind(props => self.child(props, "shd"))
  if theme is Some(slot) &&
    original is Some(id) &&
    self.nodes[id]
    .attribute("themeFill", uri=word_uri)
    .map(word_theme_color_name) ==
    Some(slot) &&
    self.nodes[id].attribute("val", uri=word_uri).unwrap_or("clear") == "clear" {
    // Reapplying the same binding keeps its imported cache and luminance transforms.
    return Map([])
  }
  let patch = attributes.copy()
  patch["themeFill"] = theme
  patch["themeFillTint"] = None
  patch["themeFillShade"] = None
  if theme is Some(slot) {
    patch["fill"] = Some(
      themes
      .get(theme_color_name(slot))
      .unwrap_or_else(() => {
        @failure.reject(
          "protected-content",
          "Missing table fill theme color: " + slot,
        )
      }),
    )
  }
  patch
}
