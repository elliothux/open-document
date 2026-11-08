///|
fn Ref::diagram_child(self : Ref, name : String) -> Ref raise @failure.Failure {
  {
    tree: self.tree,
    node: self.tree.required(self.node.id, name, uri=diagram_uri),
  }
}

///|
fn diagram_part(
  opc : @opc.Package,
  cache : Map[String, Tree],
  data : Ref,
  key : String,
  kind : String,
  parts : Map[String, @xml.Document],
) -> Tree raise @failure.Failure {
  let id = data
    .child("relIds", uri=diagram_uri)
    .bind(n => n.node.attribute(key, uri=relationship_uri))
    .unwrap_or("")
  let part = relationship_target(
    opc,
    data.tree.part,
    id,
    relationship_uri + "/" + kind,
    parts,
  ).unwrap_or_error(
    @failure.Failure(
      code="unsupported-style",
      message="Missing internal SmartArt " + kind + " relationship",
      part=data.tree.part,
      offset=-1,
    ),
  )
  load_tree(opc, cache, part, parts~)
}

///|
fn diagram_named(
  tree : Tree,
  name : String,
  value : String,
) -> Ref raise @failure.Failure {
  let nodes = tree.document
    .nodes()
    .filter(n => {
      n.uri == diagram_uri &&
      n.name == name &&
      n.attribute("name") == Some(value)
    })
  guard nodes is [node] else {
    @failure.reject(
      "unsupported-style",
      "Missing or ambiguous SmartArt " + name + ": " + value,
    )
  }
  { tree, node, }
}

///|
fn diagram_markup(source : Ref) -> String raise @failure.Failure {
  source.tree.standalone_markup(source.tree.document, source.node.id)
}

///|
fn diagram_color_markup(
  colors : Ref,
  kind : String,
) -> String raise @failure.Failure {
  let list = colors
    .child(kind + "ClrLst", uri=diagram_uri)
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="Missing SmartArt color list",
        part=colors.tree.part,
        offset=-1,
      ),
    )
  guard list.node.attribute("meth").unwrap_or("span") == "repeat" &&
    list.tree.children.get(list.node.id) is Some([color]) &&
    color.uri == drawing_uri else {
    @failure.reject(
      "unsupported-style", "SmartArt requires a repeated single color",
    )
  }
  diagram_markup({ tree: list.tree, node: color, })
}

///|
fn diagram_style_markup(
  style : Ref,
  colors : Ref,
) -> String raise @failure.Failure {
  guard style.child("style", uri=diagram_uri) is Some(references) &&
    references.child("effectRef").bind(n => n.node.attribute("idx")) ==
    Some("0") &&
    style
    .child("sp3d", uri=diagram_uri)
    .map(n => {
      n.node.attributes.is_empty() &&
      n.tree.children.get(n.node.id).unwrap_or([]).is_empty()
    })
    .unwrap_or(true) &&
    style
    .child("txPr", uri=diagram_uri)
    .map(n => {
      n.node.attributes.is_empty() &&
      n.tree.children.get(n.node.id).unwrap_or([]).is_empty()
    })
    .unwrap_or(true) else {
    @failure.reject("unsupported-style", "SmartArt requires flat shape styling")
  }
  let output = StringBuilder()
  if style.child("scene3d", uri=diagram_uri) is Some(scene) {
    guard scene.child("camera") is Some(camera) &&
      camera.node.attributes
      is [{ name: "prst", uri: "", value: "orthographicFront", .. }] &&
      camera.tree.children.get(camera.node.id).unwrap_or([]).is_empty() else {
      @failure.reject("unsupported-style", "SmartArt camera requires support")
    }
  }
  output.write_string("<p:style>")
  for (kind, list) in [("ln", "lin"), ("fill", "fill")] {
    guard references.child(kind + "Ref") is Some(reference) else {
      @failure.reject("unsupported-style", "Missing SmartArt style reference")
    }
    let index = number(reference.node.attribute("idx").unwrap_or("0"), 0, 1009).to_int()
    output.write_string(
      "<a:\{kind}Ref idx=\"\{index}\">\{diagram_color_markup(colors, list)}</a:\{kind}Ref>",
    )
  }
  output.write_string(
    "<a:effectRef idx=\"0\"><a:srgbClr val=\"000000\"/></a:effectRef>",
  )
  guard references.child("fontRef") is Some(font) else {
    @failure.reject("unsupported-style", "Missing SmartArt font reference")
  }
  output.write_string(diagram_markup(font))
  output.write_string("</p:style>")
  output.to_string()
}

///|
fn diagram_text_markup(
  point : Ref,
  maximum : Double,
) -> String raise @failure.Failure {
  guard point.child("t", uri=diagram_uri) is Some(text) else {
    @failure.reject("unsupported-style", "Missing SmartArt content text")
  }
  let output = StringBuilder()
  output.write_string(
    "<p:txBody><a:bodyPr anchor=\"ctr\" wrap=\"none\" lIns=\"0\" rIns=\"0\" tIns=\"0\" bIns=\"0\"/><a:lstStyle><a:lvl1pPr algn=\"ctr\"><a:defRPr sz=\"\{(maximum * 100).to_int()}\"/></a:lvl1pPr></a:lstStyle>",
  )
  for node in text.tree.children.get(text.node.id).unwrap_or([]) {
    guard node.uri == drawing_uri &&
      ["bodyPr", "lstStyle", "p"].contains(node.name) else {
      @failure.reject("unsupported-style", "Unsupported SmartArt text content")
    }
    if node.name != "p" {
      guard node.attributes.is_empty() &&
        text.tree.children.get(node.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "unsupported-style", "SmartArt text frame overrides require support",
        )
      }
      continue
    }
    let paragraph : Ref = { tree: text.tree, node, }
    guard paragraph.child("pPr") is None else {
      @failure.reject(
        "unsupported-style", "SmartArt paragraph overrides require support",
      )
    }
    output.write_string(diagram_markup(paragraph))
  }
  output.write_string("</p:txBody>")
  output.to_string()
}

///|
fn read_diagram_native(
  opc : @opc.Package,
  cache : Map[String, Tree],
  frame : Object,
  data : Ref,
  root : Ref,
  theme : Theme,
  master : Tree,
  defaults : Ref?,
  parts : Map[String, @xml.Document],
  page_number : String,
  date_time : DateTime?,
  media : Map[String, Bytes],
) -> Array[Object] raise @failure.Failure {
  let layout = diagram_part(opc, cache, data, "lo", "diagramLayout", parts)
  let definition = layout.root("layoutDef", uri=diagram_uri)
  guard definition.attribute("uniqueId") ==
    Some("urn:microsoft.com/office/officeart/2005/8/layout/orgChart1") else {
    @failure.reject(
      "unsupported-style", "SmartArt requires another native layout algorithm",
    )
  }
  let layout_root = layout.required(
    definition.id,
    "layoutNode",
    uri=diagram_uri,
  )
  let hierarchy : Ref = { tree: layout, node: layout_root, }
  diagram_check_algorithm(hierarchy, "hierChild", { "linDir": "fromL" })
  diagram_check_algorithm(
    diagram_named(layout, "layoutNode", "hierRoot1"),
    "hierRoot",
    Map([]),
  )
  diagram_check_algorithm(
    diagram_named(layout, "layoutNode", "hierChild2"),
    "hierChild",
    Map([]),
  )
  diagram_check_algorithm(
    diagram_named(layout, "layoutNode", "hierChild3"),
    "hierChild",
    {
      "chAlign": "l",
      "linDir": "fromL",
      "secChAlign": "t",
      "secLinDir": "fromT",
    },
  )
  let variables = hierarchy.child("varLst", uri=diagram_uri)
  guard variables
    .bind(n => n.child("orgChart", uri=diagram_uri))
    .map(n => flag(n.node, "val"))
    .unwrap_or(false) &&
    [None, Some("norm")].contains(
      variables
      .bind(n => n.child("dir", uri=diagram_uri))
      .bind(n => n.node.attribute("val")),
    ) else {
    @failure.reject(
      "unsupported-style", "SmartArt requires default hierarchy direction",
    )
  }
  // shortcut: default orgChart1 branches with leaf children; add deeper branch algorithms when needed.
  for node in root.tree.document.nodes() {
    if node.uri == diagram_uri &&
      node.name == "hierBranch" &&
      ![None, Some("init")].contains(node.attribute("val")) {
      @failure.reject(
        "unsupported-style", "SmartArt branch override requires support",
      )
    }
  }
  let styles = diagram_part(opc, cache, data, "qs", "diagramQuickStyle", parts)
  ignore(styles.root("styleDef", uri=diagram_uri))
  let colors = diagram_part(opc, cache, data, "cs", "diagramColors", parts)
  ignore(colors.root("colorsDef", uri=diagram_uri))
  let roots = diagram_content(root)
  if root.child("whole", uri=diagram_uri) is Some(whole) {
    guard whole.node.attributes.is_empty() &&
      whole.tree.children.get(whole.node.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-style", "SmartArt whole-diagram overrides require support",
      )
    }
  }
  let boxes = diagram_hierarchy_boxes(roots, hierarchy, frame.geometry.unwrap())
  diagram_check_algorithm(
    diagram_named(layout, "layoutNode", "rootComposite1"),
    "composite",
    Map([]),
  )
  for role in ["rootComposite", "rootComposite3"] {
    diagram_check_algorithm(
      diagram_named(layout, "layoutNode", role),
      "composite",
      Map([]),
    )
    guard diagram_constraint(hierarchy, "h", role) ==
      diagram_constraint(hierarchy, "h", "rootComposite1") &&
      diagram_constraint(hierarchy, "w", role) ==
      diagram_constraint(hierarchy, "w", "rootComposite1") else {
      @failure.reject(
        "unsupported-style", "SmartArt requires uniform node heights",
      )
    }
  }
  let reason = "Native SmartArt hierarchy is read-only"
  let (background, alpha) = root
    .child("bg", uri=diagram_uri)
    .map(n => fill_rgba(theme, [n]))
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
  let by_key : Map[String, Object] = Map([])
  let mut text_units = 0
  for index, (node, geometry) in boxes {
    let role = if node.kind == "asst" {
      "rootText3"
    } else if roots.any(n => n.key == node.key) {
      "rootText1"
    } else {
      "rootText"
    }
    let presentations = root.tree.document
      .nodes()
      .filter(n => {
        n.uri == diagram_uri &&
        n.name == "prSet" &&
        n.attribute("presAssocID") == Some(node.key) &&
        n.attribute("presName") == Some(role)
      })
    guard presentations is [presentation] &&
      presentation.attribute("presStyleLbl") is Some(label) else {
      @failure.reject(
        "unsupported-style", "Missing SmartArt text presentation association",
      )
    }
    guard node.source
      .child("spPr", uri=diagram_uri)
      .map(n => {
        n.node.attributes.is_empty() &&
        n.tree.children.get(n.node.id).unwrap_or([]).is_empty()
      })
      .unwrap_or(true) else {
      @failure.reject(
        "unsupported-style", "SmartArt shape overrides require support",
      )
    }
    if node.source.child("prSet", uri=diagram_uri) is Some(properties) {
      guard properties.node.attributes.all(a => {
          a.uri.is_empty() && ["phldr", "phldrT"].contains(a.name)
        }) &&
        properties.tree.children
        .get(properties.node.id)
        .unwrap_or([])
        .is_empty() else {
        @failure.reject(
          "unsupported-style", "SmartArt node overrides require support",
        )
      }
    }
    let text_layout = diagram_named(layout, "layoutNode", role)
    diagram_check_algorithm(text_layout, "tx", Map([]))
    let shape = text_layout.diagram_child("shape")
    guard shape.node.attribute("type") == Some("rect") &&
      !flag(shape.node, "hideGeom") &&
      shape.node
      .attribute("blip", uri=relationship_uri)
      .unwrap_or("")
      .is_empty() else {
      @failure.reject(
        "unsupported-style", "SmartArt hierarchy requires rectangular text nodes",
      )
    }
    let constraints = text_layout.diagram_child("constrLst")
    let font = layout
      .all(constraints.node.id, "constr", uri=diagram_uri)
      .filter(n => n.attribute("type") == Some("primFontSz"))
    let rules = text_layout.diagram_child("ruleLst")
    let minimum = layout
      .all(rules.node.id, "rule", uri=diagram_uri)
      .filter(n => n.attribute("type") == Some("primFontSz"))
    guard font is [font] && minimum is [minimum] else {
      @failure.reject(
        "unsupported-style", "SmartArt requires bounded font constraints",
      )
    }
    let max_font = diagram_decimal(font, "val")
    let min_font = diagram_decimal(minimum, "val")
    guard min_font >= 1 && max_font >= min_font else {
      @failure.reject("unsupported-style", "Invalid SmartArt font range")
    }
    let margins = layout
      .all(constraints.node.id, "constr", uri=diagram_uri)
      .filter(n => {
        [Some("lMarg"), Some("rMarg"), Some("tMarg"), Some("bMarg")].contains(
          n.attribute("type"),
        )
      })
    guard margins.length() == 4 &&
      margins.all(n => n.attribute("refType") == Some("primFontSz")) else {
      @failure.reject("unsupported-style", "Unsupported SmartArt text margins")
    }
    let margin = diagram_decimal(margins[0], "fact")
    guard margins.all(n => diagram_decimal(n, "fact") == margin) &&
      ["lMarg", "rMarg", "tMarg", "bMarg"].all(kind => {
        margins.filter(n => n.attribute("type") == Some(kind)).length() == 1
      }) else {
      @failure.reject(
        "unsupported-style", "SmartArt requires uniform text margins",
      )
    }
    let style = diagram_named(styles, "styleLbl", label)
    let color = diagram_named(colors, "styleLbl", label)
    for kind in ["txFillClrLst", "txLinClrLst", "txEffectClrLst"] {
      guard color
        .child(kind, uri=diagram_uri)
        .map(n => n.tree.children.get(n.node.id).unwrap_or([]).is_empty())
        .unwrap_or(true) else {
        @failure.reject(
          "unsupported-style", "SmartArt text color-list overrides require support",
        )
      }
    }
    let markup = object_markup(
        (index + 1).to_string(),
        "rect",
        0,
        0,
        geometry.width,
        geometry.height,
        "",
      )
      .replace(
        old="<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>",
        new="",
      )
      .replace(
        old="<a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln>",
        new="",
      )
      .replace(
        old=object_text_markup(""),
        new=diagram_style_markup(style, color) +
          diagram_text_markup(node.source, max_font),
      )
    let document = @xml.Document::parse(
      @utf8.encode(markup),
      root.tree.part,
      128,
      1048576,
    )
    let tree = Tree::new(root.tree.part, document)
    let object = read_object(
      opc,
      theme,
      [{ tree, node: tree.root("sp"), }],
      master,
      defaults,
      @layout.Matrix::identity(),
      reason,
      parts,
      page_number,
      date_time,
      media,
    )
    let object = {
      ..object,
      id: frame.id + "/native-" + node.key,
      parent: frame.id,
      geometry: Some(geometry),
      diagram_font: Some(Layout(min_font, max_font, margin)),
    }
    text_units += object.text().length()
    guard text_units <= 32767 else {
      @failure.reject("limit-exceeded", "SmartArt text exceeds content budget")
    }
    by_key[node.key] = object
    output.push(object)
  }
  let connectors : Array[Object] = []
  for parent in roots {
    let source = by_key[parent.key]
    let a = source.geometry.unwrap()
    for child in parent.children {
      let b = by_key[child.key].geometry.unwrap()
      let links = root.tree.document
        .nodes()
        .filter(n => {
          n.uri == diagram_uri &&
          n.name == "cxn" &&
          n.attribute("srcId") == Some(parent.key) &&
          n.attribute("destId") == Some(child.key) &&
          [None, Some("parOf")].contains(n.attribute("type"))
        })
      guard links is [link] && link.attribute("parTransId") is Some(transition) else {
        @failure.reject(
          "unsupported-style", "Missing SmartArt parent transition",
        )
      }
      let labels = root.tree.document
        .nodes()
        .filter(n => {
          n.uri == diagram_uri &&
          n.name == "prSet" &&
          n.attribute("presAssocID") == Some(transition) &&
          n.attribute("presStyleLbl") is Some(_)
        })
      guard labels is [label] && label.attribute("presStyleLbl") is Some(label) else {
        @failure.reject("unsupported-style", "Missing SmartArt connector style")
      }
      let markup = object_markup("1", "line", 0, 0, 1, 1, "")
        .replace(
          old="<a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln>",
          new="",
        )
        .replace(
          old="</p:sp>",
          new=diagram_style_markup(
              diagram_named(styles, "styleLbl", label),
              diagram_named(colors, "styleLbl", label),
            ) +
            "</p:sp>",
        )
      let document = @xml.Document::parse(
        @utf8.encode(markup),
        root.tree.part,
        128,
        1048576,
      )
      let tree = Tree::new(root.tree.part, document)
      let connector = read_object(
        opc,
        theme,
        [{ tree, node: tree.root("sp"), }],
        master,
        defaults,
        @layout.Matrix::identity(),
        reason,
        parts,
        page_number,
        date_time,
        media,
      )
      let x = a.width / 2
      let inverse = a.matrix.inverse()
      let (bx, by) = inverse.point(b.matrix.e, b.matrix.f)
      let points = if child.kind == "asst" {
        [
          (x, a.height),
          (x, by + b.height / 2),
          (bx + b.width, by + b.height / 2),
        ]
      } else {
        let bend = by -
          diagram_constraint(hierarchy, "sp", "hierRoot1") * a.width / 2
        [
          (x, a.height),
          (x, bend),
          (bx + b.width / 2, bend),
          (bx + b.width / 2, by),
        ]
      }
      let left = points.fold(init=points[0].0, (v, p) => v.min(p.0))
      let top = points.fold(init=points[0].1, (v, p) => v.min(p.1))
      let width = (points.fold(init=left, (v, p) => v.max(p.0)) - left).max(
        0.0000001,
      )
      let height = (points.fold(init=top, (v, p) => v.max(p.1)) - top).max(
        0.0000001,
      )
      connectors.push({
        ..connector,
        id: frame.id + "/native-link-" + transition,
        parent: frame.id,
        kind: "shape",
        preset: "line",
        fill: "",
        geometry: Some(
          geometry_in_parent(
            left,
            top,
            width,
            height,
            0,
            false,
            false,
            a.matrix,
          ),
        ),
        polyline: points.map(p => ((p.0 - left) / width, (p.1 - top) / height)),
        paragraphs: [],
        diagram_font: None,
      })
    }
  }
  [output[0], ..connectors, ..output[1:]]
}
