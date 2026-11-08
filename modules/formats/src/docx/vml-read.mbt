///|
let vml_uri = "urn:schemas-microsoft-com:vml"

///|
let vml_word_uri = "urn:schemas-microsoft-com:office:word"

///|
fn vml_style(
  source : String,
  allowed : Array[String],
) -> Map[String, String] raise @failure.Failure {
  guard source.length() <= 4096 else {
    @failure.reject("limit-exceeded", "VML style exceeds budget")
  }
  let result : Map[String, String] = Map([])
  for declaration in source.split(";") {
    if declaration.trim().is_empty() {
      continue
    }
    guard declaration.split(":").to_array() is [name, value] else {
      @failure.reject("unsupported-layout", "Invalid VML style declaration")
    }
    let name = name.trim().to_owned().to_lower()
    let value = value.trim().to_owned()
    guard allowed.contains(name) && !value.is_empty() && !result.contains(name) else {
      @failure.reject(
        "unsupported-layout", "Unknown or duplicate VML style property",
      )
    }
    result[name] = value
  }
  result
}

///|
fn vml_points(source : String) -> Double raise @failure.Failure {
  let source = source.trim().to_owned().to_lower()
  let value = if source == "0" {
    0.0
  } else {
    guard source.has_suffix("pt") else {
      @failure.reject(
        "unsupported-layout", "VML lengths require explicit points",
      )
    }
    @string.parse_double(source[:source.length() - 2]) catch {
      _ => @failure.reject("unsupported-layout", "Invalid VML length")
    }
  }
  guard !value.is_nan() && !value.is_inf() && value.abs() <= 14400 else {
    @failure.reject("limit-exceeded", "VML length exceeds drawing bounds")
  }
  value
}

///|
fn vml_flag(
  node : @xml.Node,
  name : String,
  fallback : Bool,
) -> Bool raise @failure.Failure {
  match node.attribute(name) {
    None => fallback
    Some("f" | "false" | "0") => false
    Some("t" | "true" | "1") => true
    _ => @failure.reject("unsupported-layout", "Invalid VML on/off value")
  }
}

///|
fn vml_color(source : String) -> String raise @failure.Failure {
  let rgb = match source.to_lower() {
    "black" => "000000"
    "white" => "ffffff"
    value if value.has_prefix("#") => value[1:].to_owned()
    _ => ""
  }
  guard rgb.length() == 6 && rgb.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject(
      "unsupported-layout", "VML paint requires explicit RGB colors",
    )
  }
  rgb
}

///|
fn WordTree::vml_rectangle_type(
  self : WordTree,
  reference : String,
) -> Unit raise @failure.Failure {
  guard reference.has_prefix("#") else {
    @failure.reject(
      "unsupported-layout", "VML shape requires a local rectangle type",
    )
  }
  let types = self.order.filter(id => {
    self.nodes[id].uri == vml_uri &&
    self.nodes[id].name == "shapetype" &&
    self.nodes[id].attribute("id") == Some(reference[1:].to_owned())
  })
  guard types is [id] else {
    @failure.reject("unsupported-layout", "Missing or duplicate VML shape type")
  }
  let node = self.nodes[id]
  guard node.attribute("coordsize") == Some("21600,21600") &&
    node.attribute("path") == Some("m,l,21600r21600,l21600,xe") &&
    node.attribute("spt", uri="urn:schemas-microsoft-com:office:office") ==
    Some("202") &&
    node.attributes.all(a => {
      (a.uri.is_empty() && ["id", "coordsize", "path"].contains(a.name)) ||
      (a.uri == "urn:schemas-microsoft-com:office:office" && a.name == "spt")
    }) else {
    @failure.reject(
      "unsupported-layout", "VML custom shape geometry requires support",
    )
  }
  self.shape_children(id, ["stroke", "path"], uri=vml_uri)
  for child in self.children[id] {
    let item = self.nodes[child]
    guard self.children[child].is_empty() &&
      item.text.trim().is_empty() &&
      item.attributes.all(a => {
        if item.name == "stroke" {
          a.uri.is_empty() && a.name == "joinstyle" && a.value == "miter"
        } else {
          (
            a.uri.is_empty() &&
            a.name == "gradientshapeok" &&
            ["t", "true", "1"].contains(a.value)
          ) ||
          (
            a.uri == "urn:schemas-microsoft-com:office:office" &&
            a.name == "connecttype" &&
            a.value == "rect"
          )
        }
      }) else {
      @failure.reject(
        "unsupported-layout", "VML shape type paint requires support",
      )
    }
  }
}

///|
fn Session::vml_frame(
  self : Session,
  tree : WordTree,
  pict : Int32,
) -> @layout.DrawingFrame raise @failure.Failure {
  let root = tree.nodes[pict]
  guard root.uri == word_uri &&
    root.name == "pict" &&
    root.attributes.is_empty() &&
    root.text.trim().is_empty() &&
    tree.children[pict].all(id => {
      tree.nodes[id].uri == vml_uri &&
      ["shapetype", "shape", "rect"].contains(tree.nodes[id].name)
    }) else {
    @failure.reject(
      "unsupported-layout", "VML picture requires one ordinary shape",
    )
  }
  let shapes = tree.children[pict].filter(id => {
    tree.nodes[id].name != "shapetype"
  })
  guard shapes is [id] else {
    @failure.reject(
      "unsupported-layout", "VML picture requires one ordinary shape",
    )
  }
  let node = tree.nodes[id]
  guard node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      [
        "id", "type", "style", "filled", "fillcolor", "stroked", "strokecolor", "strokeweight",
      ].contains(a.name)
    }) else {
    @failure.reject(
      "unsupported-layout", "Extended VML shape attributes require support",
    )
  }
  if node.name == "shape" {
    tree.vml_rectangle_type(node.attribute("type").unwrap_or(""))
  } else {
    guard node.attribute("type") is None else {
      @failure.reject(
        "unsupported-layout", "Typed VML rectangle requires support",
      )
    }
  }
  let style = vml_style(node.attribute("style").unwrap_or(""), [
    "position", "margin-left", "margin-top", "width", "height", "z-index", "mso-position-horizontal-relative",
    "mso-position-vertical-relative", "mso-wrap-style",
  ])
  guard style.get("position") == Some("absolute") &&
    style.get("margin-left") is Some(x) &&
    style.get("margin-top") is Some(y) &&
    style.get("width") is Some(width) &&
    style.get("height") is Some(height) &&
    style.get("mso-position-horizontal-relative") is Some(horizontal) &&
    style.get("mso-position-vertical-relative") is Some(vertical) &&
    [None, Some("none")].contains(style.get("mso-wrap-style")) else {
    @failure.reject(
      "unsupported-layout", "VML placement requires absolute nonwrapping coordinates",
    )
  }
  let order = @string.parse_int64(style.get("z-index").unwrap_or("0")) catch {
    _ => @failure.reject("unsupported-layout", "Invalid VML layer order")
  }
  let anchor : @layout.DrawingAnchor = {
    horizontal: @layout.Offset(horizontal, vml_points(x)),
    vertical: @layout.Offset(vertical, vml_points(y)),
    behind: false,
    order,
    wrapping: "none",
    wrapSide: "bothSides",
    distance: { top: 0, right: 0, bottom: 0, left: 0, },
  }
  anchor.validate()
  let seen : Set[String] = Set([])
  let mut text = None
  for child in tree.children[id] {
    let item = tree.nodes[child]
    guard !seen.contains(item.name) else {
      @failure.reject("unsupported-layout", "Duplicate VML shape content")
    }
    seen.add(item.name)
    if item.uri == vml_uri && item.name == "textbox" {
      text = Some(self.vml_text(tree, id, child))
    } else if item.uri == vml_word_uri && item.name == "wrap" {
      // ONLYOFFICE SimpleTypes_Vml defaults CWrapType to none.
      guard item.text.trim().is_empty() &&
        tree.children[child].is_empty() &&
        item.attributes.all(a => {
          a.uri.is_empty() &&
          (match a.name {
            "type" => a.value == "none"
            "anchorx" => a.value == horizontal
            "anchory" => a.value == vertical
            _ => false
          })
        }) else {
        @failure.reject("unsupported-layout", "VML wrapping requires support")
      }
    } else {
      @failure.reject(
        "unsupported-layout", "VML shape effects and nested content require support",
      )
    }
  }
  let stroke = if vml_flag(node, "stroked", true) {
    vml_color(node.attribute("strokecolor").unwrap_or("black"))
  } else {
    ""
  }
  let paint : @layout.BasicShape = {
    preset: "rect",
    fill: if vml_flag(node, "filled", true) {
      vml_color(node.attribute("fillcolor").unwrap_or("white"))
    } else {
      ""
    },
    stroke,
    lineWidth: if stroke.is_empty() {
      0
    } else {
      vml_points(node.attribute("strokeweight").unwrap_or("1pt"))
    },
    points: [],
    strokeAlpha: 1,
  }
  let frame : @layout.DrawingFrame = {
    width: vml_points(width),
    height: vml_points(height),
    effectExtent: (0, 0, 0, 0),
    anchor: Some(anchor),
    content: text
    .map(text => @layout.TextBox(paint, text))
    .unwrap_or(@layout.Shape(paint)),
  }
  frame.validate()
  frame
}
