///|
priv struct Theme {
  tree : Tree
  colors : Map[String, Ref]
  fonts : Map[String, Map[String, String]]
  mapping : Map[String, String]
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
  { tree, colors, fonts, mapping, }
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
fn color_rgba(
  theme : Theme,
  container : Ref,
  placeholder~ : Ref? = None,
  depth~ : Int = 0,
) -> (String, Double) raise @failure.Failure {
  guard depth < 8 else {
    @failure.reject("malformed-pptx", "Cyclic theme color")
  }
  let candidates = container.tree.children
    .get(container.node.id)
    .unwrap_or([])
    .filter(node => node.uri == drawing_uri)
  guard candidates is [node] else {
    @failure.reject("unsupported-style", "Unsupported color declaration")
  }
  let value = node.attribute("val").unwrap_or("")
  let base = match node.name {
    "srgbClr" => (value, 1.0)
    "sysClr" => (node.attribute("lastClr").unwrap_or(""), 1.0)
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
        -100000,
        1000000,
      ) /
      100000
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
      "tint" => rgb = rgb.map(value => value + (1 - value) * amount)
      "shade" => rgb = rgb.map(value => value * amount)
      "lumMod" | "lumOff" => {
        let low = rgb[0].min(rgb[1]).min(rgb[2])
        let high = rgb[0].max(rgb[1]).max(rgb[2])
        let luminance = (high + low) / 2
        let next = (if modifier.name == "lumMod" {
            luminance * amount
          } else {
            luminance + amount
          })
          .max(0)
          .min(1)
        let chroma = high - low
        let saturation = if chroma == 0 {
          0.0
        } else {
          chroma / (1.0 - (2.0 * luminance - 1).abs()).max(0.000001)
        }
        let next_chroma = (1.0 - (2.0 * next - 1).abs()) * saturation
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
