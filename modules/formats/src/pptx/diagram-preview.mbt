///|
let diagram_uri = "http://schemas.openxmlformats.org/drawingml/2006/diagram"

///|
let diagram_drawing_uri = "http://schemas.microsoft.com/office/drawing/2008/diagram"

///|
fn diagram_view(source : Tree) -> Tree {
  let nodes = Map([])
  let children : Map[Int32, Array[@xml.Node]] = Map([])
  // Cached shapes share PresentationML semantics; the view keeps the original XML.
  for node in source.document.nodes() {
    let node = if node.uri == diagram_drawing_uri {
      { ..node, uri: presentation_uri, }
    } else {
      node
    }
    nodes[node.id] = node
    children.get_or_init(node.parent, () => []).push(node)
  }
  { ..source, nodes, children, }
}

///|
fn diagram_text_rect(
  source : Ref,
) -> (Double, Double, Double, Double)? raise @failure.Failure {
  if source.child("txXfrm", uri=presentation_uri) is Some(text) {
    let shape = source
      .child("spPr", uri=presentation_uri)
      .bind(p => p.child("xfrm"))
      .unwrap_or_error(
        @failure.Failure(
          code="unsupported-style",
          message="Cached SmartArt text has no shape transform",
          part=source.tree.part,
          offset=-1,
        ),
      )
    guard text.node.attributes.all(a => {
        a.uri.is_empty() &&
        (
          a.name == "rot" ||
          (
            ["flipH", "flipV"].contains(a.name) &&
            ["0", "1", "false", "true"].contains(a.value)
          )
        )
      }) &&
      text.tree.children
      .get(text.node.id)
      .unwrap_or([])
      .all(n => n.uri == drawing_uri && ["off", "ext"].contains(n.name)) &&
      number(text.node.attribute("rot").unwrap_or("0"), -21600000, 21600000) ==
      number(shape.node.attribute("rot").unwrap_or("0"), -21600000, 21600000) &&
      flag(text.node, "flipH") == flag(shape.node, "flipH") &&
      flag(text.node, "flipV") == flag(shape.node, "flipV") else {
      @failure.reject(
        "unsupported-style", "Cached SmartArt text transform requires support",
      )
    }
    let frames = [text, shape].map(frame => {
      [("off", "x"), ("off", "y"), ("ext", "cx"), ("ext", "cy")].map(item => {
        number(
          frame.child(item.0).bind(p => p.node.attribute(item.1)).unwrap_or(""),
          if item.0 == "ext" {
            0
          } else {
            -182880000
          },
          182880000,
        )
      })
    })
    let a = frames[0]
    let b = frames[1]
    if b[2] == 0 || b[3] == 0 {
      guard a == b else {
        @failure.reject(
          "unsupported-style", "Cached text requires a nonzero shape frame",
        )
      }
      return None
    }
    return Some(
      (
        (a[0] - b[0]) / b[2],
        (a[1] - b[1]) / b[3],
        (a[0] - b[0] + a[2]) / b[2],
        (a[1] - b[1] + a[3]) / b[3],
      ),
    )
  }
  None
}

///|
fn read_diagram_preview(
  opc : @opc.Package,
  cache : Map[String, Tree],
  frame : Object,
  theme : Theme,
  master : Tree,
  defaults : Ref?,
  parts : Map[String, @xml.Document],
  page_number : String,
  date_time : DateTime?,
  media : Map[String, Bytes],
) -> Array[Object]? raise @failure.Failure {
  if frame.source.node.name != "graphicFrame" {
    return None
  }
  let data = frame.source.child("graphic").bind(g => g.child("graphicData"))
  guard data is Some(data) && data.node.attribute("uri") == Some(diagram_uri) else {
    return None
  }
  guard frame.shadow.map(s => s.alpha == 0).unwrap_or(true) &&
    frame.geometry is Some(geometry) &&
    frame.diagnostic == "Unsupported object geometry: graphicFrame/rect" else {
    @failure.reject("unsupported-style", "Unsupported SmartArt frame")
  }
  let reason = "Native SmartArt cached drawing is read-only"
  let link = data
    .child("relIds", uri=diagram_uri)
    .bind(n => n.node.attribute("dm", uri=relationship_uri))
    .unwrap_or("")
  let model_part = relationship_target(
    opc,
    frame.source.tree.part,
    link,
    relationship_uri + "/diagramData",
    parts,
  ).unwrap_or_error(
    @failure.Failure(
      code="unsupported-style",
      message="Missing internal SmartArt data relationship",
      part=frame.source.tree.part,
      offset=-1,
    ),
  )
  let model = load_tree(opc, cache, model_part, parts~)
  let root : Ref = {
    tree: model,
    node: model.root("dataModel", uri=diagram_uri),
  }
  let extensions = root
    .child("extLst", uri=diagram_uri)
    .map(list => {
      model
      .all(list.node.id, "ext")
      .filter(n => n.attribute("uri") == Some(diagram_drawing_uri))
    })
    .unwrap_or([])
  if extensions.is_empty() {
    return Some(
      read_diagram_native(
        opc, cache, frame, data, root, theme, master, defaults, parts, page_number,
        date_time, media,
      ),
    )
  }
  guard extensions is [extension] else {
    @failure.reject(
      "unsupported-style", "SmartArt requires native layout without a cached drawing",
    )
  }
  let extension : Ref = { tree: model, node: extension, }
  let drawing_link = extension
    .child("dataModelExt", uri=diagram_drawing_uri)
    .bind(n => n.node.attribute("relId"))
    .unwrap_or("")
  let kind = "http://schemas.microsoft.com/office/2007/relationships/diagramDrawing"
  let from_slide = relationship_target(
    opc,
    frame.source.tree.part,
    drawing_link,
    kind,
    parts,
  )
  let from_model = relationship_target(
    opc, model_part, drawing_link, kind, parts,
  )
  guard !(from_slide is Some(a) && from_model is Some(b) && a != b) else {
    @failure.reject("malformed-pptx", "Ambiguous SmartArt drawing relationship")
  }
  let drawing_part = (match from_slide {
    Some(part) => Some(part)
    None => from_model
  }).unwrap_or_error(
    @failure.Failure(
      code="unsupported-style",
      message="Missing internal SmartArt drawing relationship",
      part=model_part,
      offset=-1,
    ),
  )
  let drawing = load_tree(opc, cache, drawing_part, parts~)
  let drawing_root = drawing.root("drawing", uri=diagram_drawing_uri)
  let tree = diagram_view(drawing)
  let shapes = tree.required(drawing_root.id, "spTree", uri=presentation_uri)
  let group = tree.one(shapes.id, "grpSpPr", uri=presentation_uri)
  guard group
    .map(n => {
      n.attributes.is_empty() &&
      tree.children.get(n.id).unwrap_or([]).is_empty()
    })
    .unwrap_or(true) else {
    @failure.reject(
      "unsupported-style", "Cached SmartArt root transform requires support",
    )
  }
  let items = tree.children
    .get(shapes.id)
    .unwrap_or([])
    .filter(n => !["nvGrpSpPr", "grpSpPr"].contains(n.name))
  if items.is_empty() {
    return Some(
      read_diagram_native(
        opc, cache, frame, data, root, theme, master, defaults, parts, page_number,
        date_time, media,
      ),
    )
  }
  let (background, alpha) = root
    .child("bg", uri=diagram_uri)
    .map(bg => fill_rgba(theme, [bg]))
    .unwrap_or(("", 1.0))
  let output : Array[Object] = [
    {
      ..frame,
      kind: "diagram",
      diagnostic: "",
      read_only: reason,
      text_reason: reason,
      fill: background,
      fill_alpha: alpha,
      stroke: "",
      gradient: None,
    },
  ]
  let fonts = cached_diagram_fonts(opc, cache, data, root, parts)
  for node in items {
    guard output.length() < 4096 else {
      @failure.reject(
        "limit-exceeded", "SmartArt cached drawing exceeds object budget",
      )
    }
    guard node.uri == presentation_uri &&
      ["sp", "pic", "cxnSp"].contains(node.name) else {
      @failure.reject("unsupported-style", "Unsupported cached SmartArt object")
    }
    let source : Ref = { tree, node, }
    let text_rect = diagram_text_rect(source)
    let object = read_object(
      opc,
      theme,
      [source],
      master,
      defaults,
      geometry.matrix,
      reason,
      parts,
      page_number,
      date_time,
      media,
    )
    output.push({
      ..object,
      id: frame.id + "/cache-" + node.id.to_string(),
      parent: frame.id,
      text_rect,
      diagram_font: if object.diagnostic.is_empty() && !object.text().is_empty() {
        fonts.get(source.node.attribute("modelId").unwrap_or(""))
      } else {
        None
      },
      read_only: reason,
      text_reason: reason,
    })
  }
  Some(output)
}
