///|
let theme_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
let theme_slots : Array[String] = [
  "dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5",
  "accent6", "hlink", "folHlink",
]

///|
fn Session::theme_part(self : Session) -> String? raise @failure.Failure {
  let mut result = None
  for rel in self.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" {
      guard !rel.external && result is None else {
        @failure.reject(
          "unsupported-layout", "External or duplicate themes are unsupported",
        )
      }
      let root = self.part_xml(rel.target).nodes()[0]
      guard root.uri == theme_uri && root.name == "theme" else {
        @failure.reject("invalid-style", "Invalid theme root", part=rel.target)
      }
      result = Some(rel.target)
    }
  }
  result
}

///|
fn theme_child(
  tree : WordTree,
  parent : Int,
  name : String,
) -> Int raise @failure.Failure {
  let nodes = tree.children[parent].filter(id => {
    tree.nodes[id].uri == theme_uri && tree.nodes[id].name == name
  })
  guard nodes is [id] else {
    @failure.reject(
      "protected-content",
      "Missing or duplicate theme element: " + name,
    )
  }
  id
}

///|
fn theme_color_node(
  tree : WordTree,
  slot : String,
) -> Int raise @failure.Failure {
  let elements = theme_child(tree, 0, "themeElements")
  let scheme = theme_child(tree, elements, "clrScheme")
  let id = theme_child(tree, scheme, slot)
  let node = tree.nodes[id]
  guard node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    !tree.source[node.start:node.end].contains("<!--") &&
    !tree.source[node.start:node.end].contains("<?") &&
    tree.children[id] is [child] else {
    @failure.reject("protected-content", "Extended theme color is protected")
  }
  let color = tree.nodes[child]
  guard color.uri == theme_uri &&
    ["srgbClr", "sysClr"].contains(color.name) &&
    tree.children[child].is_empty() &&
    color.text.trim().is_empty() &&
    color.attributes.all(a => {
      a.uri.is_empty() &&
      (a.name == "val" || (color.name == "sysClr" && a.name == "lastClr"))
    }) else {
    @failure.reject("protected-content", "Extended theme color is protected")
  }
  ignore(theme_rgb(tree, child))
  child
}

///|
fn theme_rgb(tree : WordTree, id : Int) -> String raise @failure.Failure {
  let node = tree.nodes[id]
  let value = node
    .attribute(if node.name == "sysClr" { "lastClr" } else { "val" })
    .unwrap_or("")
  guard value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject("invalid-style", "Invalid theme RGB color")
  }
  value.to_lower()
}

///|
fn theme_color_name(name : String) -> String {
  match name {
    "dark1" => "dk1"
    "light1" => "lt1"
    "dark2" => "dk2"
    "light2" => "lt2"
    "hyperlink" => "hlink"
    "followedHyperlink" => "folHlink"
    _ => name
  }
}

///|
fn word_theme_color_name(name : String) -> String {
  match name {
    "dk1" => "dark1"
    "lt1" => "light1"
    "dk2" => "dark2"
    "lt2" => "light2"
    "hlink" => "hyperlink"
    "folHlink" => "followedHyperlink"
    _ => name
  }
}

///|
fn Session::theme_values(
  self : Session,
) -> Map[String, String] raise @failure.Failure {
  let result : Map[String, String] = Map([])
  if self.theme_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let elements = theme_child(tree, 0, "themeElements")
    let scheme = theme_child(tree, elements, "fontScheme")
    let minor = theme_child(tree, scheme, "minorFont")
    let fallback = tree.nodes[theme_child(tree, minor, "latin")]
      .attribute("typeface")
      .filter(v => !v.is_empty())
      .unwrap_or("Arial")
    for kind in ["major", "minor"] {
      let parent = theme_child(tree, scheme, kind + "Font")
      for
        (name, slot) in [
          ("latin", "Ascii"),
          ("latin", "HAnsi"),
          ("ea", "EastAsia"),
          ("cs", "Bidi"),
        ] {
        let value = tree.nodes[theme_child(tree, parent, name)]
          .attribute("typeface")
          .unwrap_or("")
        result[kind + slot] = if value.is_empty() { fallback } else { value }
      }
    }
    for slot in theme_slots {
      try {
        result[slot] = theme_rgb(tree, theme_color_node(tree, slot))
      } catch {
        _ => ()
      }
    }
  }
  let mapping = Map([
    ("background1", "lt1"),
    ("text1", "dk1"),
    ("background2", "lt2"),
    ("text2", "dk2"),
  ])
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    if tree.child(0, "clrSchemeMapping") is Some(id) {
      for
        (field, key) in [
          ("bg1", "background1"),
          ("t1", "text1"),
          ("bg2", "background2"),
          ("t2", "text2"),
          ("accent1", "accent1"),
          ("accent2", "accent2"),
          ("accent3", "accent3"),
          ("accent4", "accent4"),
          ("accent5", "accent5"),
          ("accent6", "accent6"),
          ("hyperlink", "hlink"),
          ("followedHyperlink", "folHlink"),
        ] {
        if tree.nodes[id].attribute(field, uri=word_uri) is Some(value) {
          let slot = theme_color_name(value)
          guard theme_slots.contains(slot) else {
            @failure.reject("invalid-style", "Invalid theme color mapping")
          }
          mapping[key] = slot
        }
      }
    }
  }
  let colors = result.copy()
  for key, slot in mapping {
    if colors.get(slot) is Some(value) {
      result[key] = value
    } else {
      result.remove(key)
    }
  }
  result
}

///|
fn theme_hex(value : StringView) -> Double raise @failure.Failure {
  let byte = @string.parse_int(value, base=16) catch {
    _ => @failure.reject("invalid-style", "Invalid theme color transform")
  }
  byte.to_double() / 255
}

///|
fn theme_text_color(
  tree : WordTree,
  parent : Int,
  fallback : String,
  values : Map[String, String],
) -> String raise @failure.Failure {
  guard tree.child(parent, "color") is Some(id) else { return fallback }
  let node = tree.nodes[id]
  theme_node_color(
    node,
    node.attribute("val", uri=word_uri).unwrap_or(fallback),
    values,
  )
}

///|
fn theme_color_reference(
  node : @xml.Node,
  fill~ : Bool = false,
) -> String? raise @failure.Failure {
  let name = node.attribute(
    if fill {
      "themeFill"
    } else {
      "themeColor"
    },
    uri=word_uri,
  )
  if name is Some(name) && name != "none" {
    guard theme_slots.contains(theme_color_name(name)) ||
      ["text1", "text2", "background1", "background2"].contains(name) else {
      @failure.reject("invalid-style", "Invalid theme color")
    }
  }
  for suffix in ["Shade", "Tint"] {
    let field = (if fill { "themeFill" } else { "theme" }) + suffix
    if node.attribute(field, uri=word_uri) is Some(value) {
      guard value.length() == 2 && value.iter().all(c => c.is_ascii_hexdigit()) else {
        @failure.reject("invalid-style", "Invalid theme color transform")
      }
    }
  }
  name
}

///|
fn theme_node_color(
  node : @xml.Node,
  fallback : String,
  values : Map[String, String],
  fill~ : Bool = false,
) -> String raise @failure.Failure {
  let name = theme_color_reference(node, fill~)
  let mut color = if name is Some(name) && name != "none" {
    values
    .get(theme_color_name(name))
    .unwrap_or_else(() => {
      @failure.reject(
        "unsupported-layout",
        "Missing or unsupported theme color: " + name,
      )
    })
  } else {
    fallback
  }
  guard color == "auto" ||
    (color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit())) else {
    @failure.reject("invalid-style", "Invalid color")
  }
  // ONLYOFFICE RtfColor applies shade then tint to HSL luminance.
  for suffix in ["Shade", "Tint"] {
    let field = (if fill { "themeFill" } else { "theme" }) + suffix
    if node.attribute(field, uri=word_uri) is Some(value) {
      if name is None || name == Some("none") {
        continue
      }
      let amount = theme_hex(value[:])
      let rgb = [0, 2, 4].map(i => theme_hex(color[i:i + 2]))
      let low = rgb[0].min(rgb[1]).min(rgb[2])
      let high = rgb[0].max(rgb[1]).max(rgb[2])
      let light = (high + low) / 2
      let next = if suffix == "Shade" {
        light * amount
      } else {
        light * amount + 1 - amount
      }
      let chroma = high - low
      let saturation = if chroma == 0 {
        0.0
      } else {
        chroma / (1.0 - (2.0 * light - 1).abs())
      }
      let next_chroma = (1.0 - (2.0 * next - 1).abs()) * saturation
      let out = StringBuilder()
      for channel in rgb {
        let v = if chroma == 0 {
          next
        } else {
          (channel - low) / chroma * next_chroma + next - next_chroma / 2
        }
        let byte = (v.clamp(min=0, max=1) * 255).round().to_int()
        out.write_char("0123456789abcdef"[byte >> 4].to_char().unwrap())
        out.write_char("0123456789abcdef"[byte & 15].to_char().unwrap())
      }
      color = out.to_string()
    }
  }
  color
}
