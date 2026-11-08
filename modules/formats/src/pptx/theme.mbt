///|
priv struct Theme {
  tree : Tree
  colors : Map[String, Ref]
  fonts : Map[String, Map[String, String]]
  mapping : Map[String, String]
  tables : TableStyleBook?
}

///|
fn read_theme(
  tree : Tree,
  layers : Array[Tree],
) -> Theme raise @failure.Failure {
  let root = tree.root("theme", uri=drawing_uri)
  let elements = tree.required(root.id, "themeElements")
  let colors = Map([])
  for
    node in tree.children
    .get(tree.required(elements.id, "clrScheme").id)
    .unwrap_or([]) {
    colors[node.name] = { tree, node, }
  }
  let fonts = Map([])
  let scheme = tree.required(elements.id, "fontScheme")
  for kind in ["major", "minor"] {
    let container = tree.required(scheme.id, kind + "Font")
    let values = Map([])
    for node in tree.children.get(container.id).unwrap_or([]) {
      values[if node.name == "font" {
        node.attribute("script").unwrap_or("")
      } else {
        node.name
      }] = node.attribute("typeface").unwrap_or("")
    }
    fonts[kind] = values
  }
  let mapping : Map[String, String] = Map([
    ("bg1", "lt1"),
    ("tx1", "dk1"),
    ("bg2", "lt2"),
    ("tx2", "dk2"),
  ])
  for layer in layers.rev() {
    let root = layer.document.nodes()[0]
    let overrides = match layer.one(root.id, "clrMap", uri=presentation_uri) {
      Some(value) => Some(value)
      None =>
        layer
        .one(root.id, "clrMapOvr", uri=presentation_uri)
        .bind(node => layer.one(node.id, "overrideClrMapping"))
    }
    if overrides is Some(node) {
      for attr in node.attributes {
        if attr.uri.is_empty() {
          mapping[attr.name] = attr.value
        }
      }
    }
  }
  { tree, colors, fonts, mapping, tables: None, }
}

///|
fn hex_color(value : String) -> Array[Double] raise @failure.Failure {
  guard value.length() == 6 else {
    @failure.reject("unsupported-style", "Invalid sRGB color")
  }
  [0, 2, 4].map(index => {
    let byte = @string.parse_int(value[index:index + 2], base=16) catch {
      _ => -1
    }
    guard byte >= 0 else {
      @failure.reject("unsupported-style", "Invalid sRGB color")
    }
    byte.to_double() / 255
  })
}

///|
fn rgb_hex(rgb : Array[Double]) -> String {
  let out = StringBuilder()
  for value in rgb {
    let byte = (value.max(0).min(1) * 255).round().to_int()
    out.write_char("0123456789abcdef"[byte >> 4].to_char().unwrap())
    out.write_char("0123456789abcdef"[byte & 15].to_char().unwrap())
  }
  out.to_string()
}

///|
fn rotate_hue(rgb : Array[Double], degrees : Double) -> Array[Double] {
  let low = rgb[0].min(rgb[1]).min(rgb[2])
  let high = rgb[0].max(rgb[1]).max(rgb[2])
  let chroma = high - low
  if chroma == 0 {
    return rgb
  }
  let hue = (if high == rgb[0] {
      (rgb[1] - rgb[2]) / chroma
    } else if high == rgb[1] {
      (rgb[2] - rgb[0]) / chroma + 2
    } else {
      (rgb[0] - rgb[1]) / chroma + 4
    }) +
    degrees / 60
  let hue = hue - (hue / 6).floor() * 6
  let middle = chroma * (1 - (hue - (hue / 2).floor() * 2 - 1).abs())
  let channels : Array[Double] = match hue.floor().to_int() {
    0 => [chroma, middle, 0]
    1 => [middle, chroma, 0]
    2 => [0, chroma, middle]
    3 => [0, middle, chroma]
    4 => [middle, 0, chroma]
    _ => [chroma, 0, middle]
  }
  channels.map(value => value + low)
}

///|
fn color_rgba(
  theme : Theme,
  container : Ref,
  placeholder~ : Ref? = None,
  depth~ : Int32 = 0,
) -> (String, Double) raise @failure.Failure {
  let candidates = container.tree.children
    .get(container.node.id)
    .unwrap_or([])
    .filter(node => node.uri == drawing_uri)
  guard candidates is [node] else {
    @failure.reject("unsupported-style", "Unsupported color declaration")
  }
  color_value_rgba(theme, { tree: container.tree, node, }, placeholder~, depth~)
}

///|
fn color_value_rgba(
  theme : Theme,
  container : Ref,
  placeholder~ : Ref? = None,
  depth~ : Int32 = 0,
) -> (String, Double) raise @failure.Failure {
  guard depth < 8 else {
    @failure.reject("malformed-pptx", "Cyclic theme color")
  }
  let node = container.node
  let value = node.attribute("val").unwrap_or("")
  let base = match node.name {
    "srgbClr" => (value, 1.0)
    "sysClr" => (node.attribute("lastClr").unwrap_or(""), 1.0)
    "prstClr" => {
      guard ["black", "white"].contains(value) &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => a.uri.is_empty() && a.name == "val") else {
        @failure.reject(
          "unsupported-style",
          "Unsupported preset color: " + value,
        )
      }
      (if value == "black" { "000000" } else { "ffffff" }, 1.0)
    }
    "schemeClr" =>
      if value == "phClr" && placeholder is Some(reference) {
        color_rgba(theme, reference, depth=depth + 1)
      } else {
        let key = theme.mapping.get(value).unwrap_or(value)
        guard theme.colors.get(key) is Some(source) else {
          @failure.reject("unsupported-style", "Unknown theme color: " + value)
        }
        color_rgba(theme, source, placeholder~, depth=depth + 1)
      }
    _ => @failure.reject("unsupported-style", "Unsupported color: " + node.name)
  }
  let mut rgb = hex_color(base.0)
  let mut alpha = base.1
  for modifier in container.tree.children.get(node.id).unwrap_or([]) {
    guard modifier.uri == drawing_uri &&
      modifier.text.trim().is_empty() &&
      modifier.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
      container.tree.children.get(modifier.id).unwrap_or([]).is_empty() else {
      @failure.reject("unsupported-style", "Unknown color transform markup")
    }
    let amount = number(
        modifier.attribute("val").unwrap_or("0"),
        if modifier.name == "hueOff" {
          -2147483648
        } else {
          -100000
        },
        if modifier.name == "hueOff" {
          2147483647
        } else {
          1000000
        },
      ) /
      (if modifier.name == "hueOff" { 60000 } else { 100000 })
    match modifier.name {
      "alpha" => {
        guard amount >= 0 && amount <= 1 else {
          @failure.reject("unsupported-style", "Invalid color opacity")
        }
        alpha = amount
      }
      "alphaMod" => {
        guard amount >= 0 else {
          @failure.reject("unsupported-style", "Invalid opacity multiplier")
        }
        alpha *= amount
      }
      "alphaOff" => alpha += amount
      "hueOff" => rgb = rotate_hue(rgb, amount)
      "tint" | "shade" => {
        guard amount >= 0 && amount <= 1 else {
          @failure.reject(
            "unsupported-style", "Invalid tint or shade percentage",
          )
        }
        // DrawingML tint/shade mix linear light; tint retains the specified base fraction.
        rgb = rgb.map(value => {
          let linear = if value <= 0.04045 {
            value / 12.92
          } else {
            @math.pow((value + 0.055) / 1.055, 2.4)
          }
          let mixed = if modifier.name == "tint" {
            1.0 - (1.0 - linear) * amount
          } else {
            linear * amount
          }
          if mixed <= 0.0031308 {
            mixed * 12.92
          } else {
            1.055 * @math.pow(mixed, 1.0 / 2.4) - 0.055
          }
        })
      }
      "lumMod" | "lumOff" | "satMod" | "satOff" => {
        guard modifier.name != "satMod" || amount >= 0 else {
          @failure.reject("unsupported-style", "Invalid saturation multiplier")
        }
        let low = rgb[0].min(rgb[1]).min(rgb[2])
        let high = rgb[0].max(rgb[1]).max(rgb[2])
        let luminance = (high + low) / 2
        let next = (if modifier.name == "lumMod" {
            luminance * amount
          } else if modifier.name == "lumOff" {
            luminance + amount
          } else {
            luminance
          })
          .max(0)
          .min(1)
        let chroma = high - low
        let saturation = if chroma == 0 {
          0.0
        } else {
          chroma / (1.0 - (2.0 * luminance - 1).abs()).max(0.000001)
        }
        let saturation = (if modifier.name == "satMod" {
            saturation * amount
          } else if modifier.name == "satOff" {
            saturation + amount
          } else {
            saturation
          })
          .max(0)
          .min(1)
        let next_chroma = (1.0 - (2.0 * next - 1).abs()) * saturation
        if chroma == 0 && modifier.name == "satOff" {
          // ONLYOFFICE CColorModifiers.graySaturation defines the achromatic offset.
          let offset = (if luminance < 128.0 / 255 {
              luminance
            } else {
              1 - luminance
            }) *
            amount
          rgb = [luminance + offset, luminance - offset, luminance - 5 * offset]
          continue
        }
        rgb = rgb.map(value => {
          if chroma == 0 {
            next
          } else {
            (value - low) / chroma * next_chroma + next - next_chroma / 2
          }
        })
      }
      _ =>
        @failure.reject(
          "unsupported-style",
          "Unsupported color transform: " + modifier.name,
        )
    }
  }
  (rgb_hex(rgb), alpha.max(0).min(1))
}

///|
fn color(
  theme : Theme,
  container : Ref,
  placeholder~ : Ref? = None,
) -> String raise @failure.Failure {
  let (rgb, alpha) = color_rgba(theme, container, placeholder~)
  guard alpha == 1 else {
    @failure.reject(
      "unsupported-style", "Transparent text or background is unsupported",
    )
  }
  rgb
}

///|
fn fill(theme : Theme, sources : Array[Ref]) -> String raise @failure.Failure {
  let (rgb, alpha) = fill_rgba(theme, sources)
  guard alpha == 1 else {
    @failure.reject(
      "unsupported-style", "Transparent text or background is unsupported",
    )
  }
  rgb
}

///|
fn fill_rgba(
  theme : Theme,
  sources : Array[Ref],
  placeholder~ : Ref? = None,
) -> (String, Double) raise @failure.Failure {
  for item in sources {
    for node in item.tree.children.get(item.node.id).unwrap_or([]) {
      if node.uri != drawing_uri {
        continue
      }
      match node.name {
        "noFill" => return ("", 1)
        "solidFill" =>
          return color_rgba(theme, { tree: item.tree, node, }, placeholder~)
        "gradFill" | "pattFill" | "blipFill" | "grpFill" =>
          @failure.reject("unsupported-style", "Unsupported fill: " + node.name)
        _ => ()
      }
    }
  }
  ("", 1)
}

///|
fn style_reference(
  theme : Theme,
  chain : Array[Ref],
  kind : String,
) -> (Ref, Ref)? raise @failure.Failure {
  for item in children(chain, "style", uri=presentation_uri) {
    if item.child(kind + "Ref") is Some(reference) {
      return theme_reference(theme, reference, kind)
    }
  }
  None
}

///|
fn theme_reference(
  theme : Theme,
  reference : Ref,
  kind : String,
) -> (Ref, Ref)? raise @failure.Failure {
  let index = number(reference.node.attribute("idx").unwrap_or("0"), 0, 1009).to_int()
  if index == 0 {
    return None
  }
  let root = theme.tree.document.nodes()[0]
  let elements = theme.tree.required(root.id, "themeElements")
  let format = theme.tree.required(elements.id, "fmtScheme")
  let container = theme.tree.required(
    format.id,
    if kind == "effect" {
      "effectStyleLst"
    } else if kind == "ln" {
      "lnStyleLst"
    } else if index >= 1001 {
      "bgFillStyleLst"
    } else {
      "fillStyleLst"
    },
  )
  let nodes = theme.tree.children.get(container.id).unwrap_or([])
  let offset = if index >= 1001 { index - 1001 } else { index - 1 }
  guard nodes.get(offset) is Some(node) else {
    @failure.reject("unsupported-style", "Invalid theme style reference")
  }
  Some(({ tree: theme.tree, node, }, reference))
}

///|
fn font_key(
  theme : Theme,
  family : String,
  text : String,
  bold : Bool,
  italic : Bool,
) -> String raise @failure.Failure {
  let mut family = family
  if family.has_prefix("+mj-") || family.has_prefix("+mn-") {
    let fonts = theme.fonts[if family.has_prefix("+mj-") {
        "major"
      } else {
        "minor"
      }]
    let script = font_script(text)
    let declared = fonts
      .get(
        if family.has_suffix("ea") {
          "ea"
        } else if family.has_suffix("cs") {
          "cs"
        } else {
          script
        },
      )
      .unwrap_or("")
    family = if declared.is_empty() {
      fonts.get(script).unwrap_or(fonts.get("latin").unwrap_or(""))
    } else {
      declared
    }
  }
  guard !family.is_empty() && family.length() <= 200 else {
    @failure.reject("missing-font", "Unresolved theme font")
  }
  family +
  (if bold { "|bold" } else { "" }) +
  (if italic { "|italic" } else { "" })
}
