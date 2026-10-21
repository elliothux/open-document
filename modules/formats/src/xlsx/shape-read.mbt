///|
fn Tree::shape_children(
  self : Tree,
  node : @xml.Node,
  names : Array[String],
  uri~ : String = picture_drawing_uri,
) -> Array[@xml.Node] raise @failure.Failure {
  let children = self.children.get(node.id).unwrap_or([])
  guard children.all(child => child.uri == uri && names.contains(child.name)) else {
    @failure.reject("unsupported-drawing", "Unknown worksheet shape content")
  }
  let seen : Map[String, Unit] = Map([])
  for child in children {
    if ["p", "r", "br"].contains(child.name) {
      continue
    }
    guard !seen.contains(child.name) else {
      @failure.reject("unsupported-drawing", "Duplicate shape " + child.name)
    }
    seen[child.name] = ()
  }
  children
}

///|
fn Session::shape_color(
  self : Session,
  tree : Tree,
  parent : @xml.Node?,
  fallback : String,
) -> String raise @failure.Failure {
  guard parent is Some(parent) else { return fallback }
  guard !(tree.picture_child(parent.id, "noFill", uri=picture_drawing_uri)
    is Some(_) &&
    tree.picture_child(parent.id, "solidFill", uri=picture_drawing_uri)
    is Some(_)) else {
    @failure.reject("unsupported-drawing", "Conflicting shape fills")
  }
  if tree.picture_child(parent.id, "noFill", uri=picture_drawing_uri)
    is Some(node) {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() else {
      @failure.reject("unsupported-drawing", "Unknown shape no-fill content")
    }
    return ""
  }
  guard tree.picture_child(parent.id, "solidFill", uri=picture_drawing_uri)
    is Some(fill) else {
    return fallback
  }
  let children = tree.shape_children(fill, ["srgbClr", "schemeClr", "sysClr"])
  guard children is [color] &&
    tree.children.get(color.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "unsupported-drawing", "Shape color transformations require support",
    )
  }
  if color.name == "schemeClr" {
    let key = color.attribute("val").unwrap_or("")
    let index = [
        "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5",
        "accent6", "hlink", "folHlink",
      ]
      .search(key)
      .unwrap_or_else(() => {
        @failure.reject("unsupported-drawing", "Unknown shape theme color")
      })
    self.theme[index]
  } else {
    color_hex(
      color
      .attribute(if color.name == "sysClr" { "lastClr" } else { "val" })
      .unwrap_or(""),
    )
  }
}

///|
fn Session::shape_text_style(
  self : Session,
  tree : Tree,
  properties : @xml.Node?,
  base : (String, Bool, Bool, Double, String),
) -> (String, Bool, Bool, Double, String) raise @failure.Failure {
  guard properties is Some(node) else { return base }
  guard node.attributes.all(a => {
    a.uri.is_empty() && ["sz", "b", "i", "lang", "dirty"].contains(a.name)
  }) else {
    @failure.reject(
      "unsupported-drawing", "Shape character formatting requires support",
    )
  }
  ignore(tree.shape_children(node, ["latin", "solidFill"]))
  let font = tree
    .picture_child(node.id, "latin", uri=picture_drawing_uri)
    .bind(latin => latin.attribute("typeface"))
    .unwrap_or(base.0)
  let font = if ["+mn-lt", "+mj-lt"].contains(font) {
    self.normal_font
  } else {
    font
  }
  let size = node
    .attribute("sz")
    .map(value => picture_integer(value, maximum=40000) / 100)
    .unwrap_or(base.3)
  guard !font.is_empty() && font.length() <= 255 && size >= 1 else {
    @failure.reject("unsupported-drawing", "Invalid shape font or size")
  }
  (
    font,
    flag(node, "b", fallback=base.1),
    flag(node, "i", fallback=base.2),
    size,
    self.shape_color(tree, Some(node), base.4),
  )
}

///|
fn Session::read_sheet_shape(
  self : Session,
  part : String,
  tree : Tree,
  frame : @xml.Node,
  source : @xml.Node,
  dimensions : Dimensions,
) -> SheetObject raise @failure.Failure {
  guard source.attributes.is_empty() else {
    @failure.reject(
      "unsupported-drawing", "Shape bindings and macros require support",
    )
  }
  ignore(
    tree.shape_children(source, ["nvSpPr", "spPr", "txBody"], uri=picture_uri),
  )
  let nv = tree.picture_node(source.id, "nvSpPr")
  ignore(tree.shape_children(nv, ["cNvPr", "cNvSpPr"], uri=picture_uri))
  let identity = tree.picture_node(nv.id, "cNvPr")
  guard tree.children.get(identity.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "unsupported-drawing", "Shape identity extensions require support",
    )
  }
  let id = identity.attribute("id").unwrap_or("")
  guard natural(id, 2147483647) > 0 else {
    @failure.reject("unsupported-drawing", "Invalid shape identity")
  }
  let nonvisual = tree.picture_node(nv.id, "cNvSpPr")
  guard nonvisual.attributes.all(a => a.uri.is_empty() && a.name == "txBox") else {
    @failure.reject("unsupported-drawing", "Unknown shape nonvisual settings")
  }
  ignore(tree.shape_children(nonvisual, ["spLocks"]))
  let properties = tree.picture_node(source.id, "spPr")
  ignore(
    tree.shape_children(properties, [
      "xfrm", "prstGeom", "solidFill", "noFill", "ln",
    ]),
  )
  if tree.picture_child(properties.id, "xfrm", uri=picture_drawing_uri)
    is Some(transform) {
    guard transform.attributes.is_empty() else {
      @failure.reject(
        "unsupported-drawing", "Shape rotation and flips require support",
      )
    }
    ignore(tree.shape_children(transform, ["off", "ext"]))
  }
  let geometry = tree.picture_node(
    properties.id,
    "prstGeom",
    uri=picture_drawing_uri,
  )
  let preset = geometry.attribute("prst").unwrap_or("")
  guard ["rect", "ellipse", "line"].contains(preset) else {
    @failure.reject("unsupported-drawing", "Unsupported worksheet shape preset")
  }
  for list in tree.shape_children(geometry, ["avLst"]) {
    guard tree.children.get(list.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-drawing", "Shape adjustments require support",
      )
    }
  }
  let line = tree.picture_child(properties.id, "ln", uri=picture_drawing_uri)
  if line is Some(line) {
    guard line.attributes.all(a => a.uri.is_empty() && a.name == "w") else {
      @failure.reject(
        "unsupported-drawing", "Shape line attributes require support",
      )
    }
    ignore(tree.shape_children(line, ["solidFill", "noFill"]))
  }
  let pen = line
    .bind(node => node.attribute("w"))
    .map(value => picture_integer(value, maximum=12700000) / 12700)
    .unwrap_or(1)
  let mut style = (self.normal_font, false, false, 12.0, "000000")
  let mut align = "left"
  let mut vertical = "top"
  let mut wrap = true
  let mut margins = (7.2, 3.6, 7.2, 3.6)
  let paragraphs : Array[String] = []
  let mut shared_style = None
  let mut shared_align = None
  if tree.picture_child(source.id, "txBody") is Some(body) {
    ignore(tree.shape_children(body, ["bodyPr", "lstStyle", "p"]))
    let body_pr = tree.picture_node(body.id, "bodyPr", uri=picture_drawing_uri)
    guard body_pr.attributes.all(a => {
      a.uri.is_empty() &&
      ["lIns", "tIns", "rIns", "bIns", "wrap", "anchor", "rtlCol"].contains(
        a.name,
      )
    }) else {
      @failure.reject(
        "unsupported-drawing", "Shape text frame settings require support",
      )
    }
    for fit in tree.shape_children(body_pr, ["noAutofit"]) {
      guard fit.attributes.is_empty() &&
        tree.children.get(fit.id).unwrap_or([]).is_empty() else {
        @failure.reject("unsupported-drawing", "Unknown shape text fit")
      }
    }
    guard !flag(body_pr, "rtlCol") else {
      @failure.reject(
        "unsupported-drawing", "Right-to-left shape columns require support",
      )
    }
    wrap = body_pr.attribute("wrap").unwrap_or("square") != "none"
    guard [None, Some("square"), Some("none")].contains(
      body_pr.attribute("wrap"),
    ) else {
      @failure.reject("unsupported-drawing", "Unknown shape text wrapping")
    }
    vertical = match body_pr.attribute("anchor").unwrap_or("t") {
      "t" => "top"
      "ctr" => "center"
      "b" => "bottom"
      _ =>
        @failure.reject(
          "unsupported-drawing", "Unknown shape vertical alignment",
        )
    }
    let values = ["lIns", "tIns", "rIns", "bIns"].mapi((i, name) => {
      body_pr
      .attribute(name)
      .map(value => picture_integer(value, maximum=182880000) / 12700)
      .unwrap_or(if i % 2 == 0 { 7.2 } else { 3.6 })
    })
    margins = (values[0], values[1], values[2], values[3])
    if tree.picture_child(body.id, "lstStyle", uri=picture_drawing_uri)
      is Some(list) {
      guard tree.children.get(list.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "unsupported-drawing", "Shape list styles require support",
        )
      }
    }
    for
      paragraph in tree.children
      .get(body.id)
      .unwrap_or([])
      .filter(node => node.name == "p") {
      ignore(tree.shape_children(paragraph, ["pPr", "r", "br", "endParaRPr"]))
      let properties = tree.picture_child(
        paragraph.id,
        "pPr",
        uri=picture_drawing_uri,
      )
      let mut base = (self.normal_font, false, false, 12.0, "000000")
      let mut paragraph_align = "left"
      if properties is Some(properties) {
        guard properties.attributes.all(a => {
          a.uri.is_empty() && a.name == "algn"
        }) else {
          @failure.reject(
            "unsupported-drawing", "Shape paragraph settings require support",
          )
        }
        ignore(tree.shape_children(properties, ["defRPr"]))
        base = self.shape_text_style(
          tree,
          tree.picture_child(properties.id, "defRPr", uri=picture_drawing_uri),
          base,
        )
        paragraph_align = match properties.attribute("algn").unwrap_or("l") {
          "l" => "left"
          "ctr" => "center"
          "r" => "right"
          _ =>
            @failure.reject(
              "unsupported-drawing", "Unsupported shape paragraph alignment",
            )
        }
      }
      guard shared_align.map(value => value == paragraph_align).unwrap_or(true) else {
        @failure.reject(
          "unsupported-drawing", "Mixed shape paragraph alignment requires support",
        )
      }
      shared_align = Some(paragraph_align)
      align = paragraph_align
      let text = StringBuilder()
      for run in tree.children.get(paragraph.id).unwrap_or([]) {
        if run.name == "pPr" {
          continue
        }
        let current = if run.name == "r" {
          ignore(tree.shape_children(run, ["rPr", "t"]))
          self.shape_text_style(
            tree,
            tree.picture_child(run.id, "rPr", uri=picture_drawing_uri),
            base,
          )
        } else if run.name == "br" {
          ignore(tree.shape_children(run, ["rPr"]))
          self.shape_text_style(
            tree,
            tree.picture_child(run.id, "rPr", uri=picture_drawing_uri),
            base,
          )
        } else {
          self.shape_text_style(tree, Some(run), base)
        }
        guard shared_style.map(value => value == current).unwrap_or(true) else {
          @failure.reject(
            "unsupported-drawing", "Mixed shape character formatting requires support",
          )
        }
        shared_style = Some(current)
        style = current
        if run.name == "r" {
          text.write_string(
            tree.picture_node(run.id, "t", uri=picture_drawing_uri).text,
          )
        } else if run.name == "br" {
          text.write_string("\n")
        }
      }
      paragraphs.push(text.to_string())
    }
  }
  let text = paragraphs.join("\n")
  guard (preset != "line" || text.is_empty()) &&
    (!flag(nonvisual, "txBox") || preset == "rect") else {
    @failure.reject("unsupported-drawing", "Unsupported shape text geometry")
  }
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Worksheet shape text exceeds budget")
  }
  let (anchor, rect) = tree.drawing_rect(frame, dimensions)
  let client = tree.picture_child(frame.id, "clientData")
  if client is Some(client) {
    guard tree.children.get(client.id).unwrap_or([]).is_empty() &&
      client.attributes.all(a => {
        a.uri.is_empty() &&
        ["fPrintsWithSheet", "fLocksWithSheet"].contains(a.name) &&
        ["0", "1", "true", "false"].contains(a.value)
      }) else {
      @failure.reject("unsupported-drawing", "Unknown shape client data")
    }
  }
  {
    id,
    part,
    tree,
    source,
    frame,
    anchor,
    rect,
    name: identity.attribute("name").unwrap_or("Shape"),
    description: identity.attribute("descr").unwrap_or(""),
    media: None,
    crop: [0, 0, 0, 0],
    shape: Some({
      preset,
      text_box: flag(nonvisual, "txBox"),
      fill: self.shape_color(tree, Some(properties), ""),
      stroke: self.shape_color(tree, line, ""),
      line_width: pen,
      text,
      font: style.0,
      bold: style.1,
      italic: style.2,
      size: style.3,
      color: style.4,
      left: margins.0,
      top: margins.1,
      right: margins.2,
      bottom: margins.3,
      wrap,
      align,
      vertical,
    }),
    printable: client
    .map(node => flag(node, "fPrintsWithSheet", fallback=true))
    .unwrap_or(true),
    visible: !flag(identity, "hidden"),
  }
}
