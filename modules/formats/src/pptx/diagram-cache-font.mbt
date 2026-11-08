///|
fn cached_diagram_fonts(
  opc : @opc.Package,
  cache : Map[String, Tree],
  data : Ref,
  root : Ref,
  parts : Map[String, @xml.Document],
) -> Map[String, DiagramFont] raise @failure.Failure {
  let output : Map[String, DiagramFont] = Map([])
  let kind = "urn:microsoft.com/office/officeart/2005/8/layout/hierarchy4"
  let id = data
    .child("relIds", uri=diagram_uri)
    .bind(n => n.node.attribute("lo", uri=relationship_uri))
    .unwrap_or("")
  guard relationship_target(
      opc,
      data.tree.part,
      id,
      relationship_uri + "/diagramLayout",
      parts,
    )
    is Some(part) else {
    return output
  }
  let layout = load_tree(opc, cache, part, parts~)
  guard layout.root("layoutDef", uri=diagram_uri).attribute("uniqueId") ==
    Some(kind) else {
    return output
  }
  // ONLYOFFICE TableHierarchy fits all non-custom text together, using the cached geometry.
  let list = root.diagram_child("ptLst")
  let nodes = root.tree.all(list.node.id, "pt", uri=diagram_uri)
  guard nodes.length() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "SmartArt presentation exceeds point budget",
    )
  }
  let points : Map[String, Ref] = Map([])
  for node in nodes {
    let key = node.attribute("modelId").unwrap_or("")
    guard !key.is_empty() && key.length() <= 128 && !points.contains(key) else {
      @failure.reject("malformed-pptx", "Invalid SmartArt point identity")
    }
    points[key] = { tree: root.tree, node, }
  }
  let connections = root.diagram_child("cxnLst")
  let links = root.tree.all(connections.node.id, "cxn", uri=diagram_uri)
  guard links.length() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "SmartArt presentation exceeds connection budget",
    )
  }
  let groups : Map[String, Array[(Int32, Ref)]] = Map([])
  for link in links {
    if link.attribute("type") != Some("presOf") {
      continue
    }
    let target = link.attribute("destId").unwrap_or("")
    guard points.contains(target) &&
      points.get(link.attribute("srcId").unwrap_or("")) is Some(point) else {
      @failure.reject("malformed-pptx", "Invalid SmartArt text association")
    }
    let order = number(link.attribute("destOrd").unwrap_or("0"), 0, 2147483647).to_int()
    groups.get_or_init(target, () => []).push((order, point))
  }
  for target, content in groups {
    let mut custom = false
    let mut placeholder = true
    let mut first = content[0]
    for (order, point) in content {
      if order < first.0 {
        first = (order, point)
      }
      guard point.child("prSet", uri=diagram_uri) is Some(properties) else {
        custom = true
        placeholder = false
        continue
      }
      let is_custom = flag(properties.node, "custT")
      let is_placeholder = flag(properties.node, "phldr")
      custom = custom || is_custom
      placeholder = placeholder &&
        is_placeholder &&
        properties.node.attribute("phldrT") is Some(_)
    }
    if custom {
      continue
    }
    let body = first.1.child("t", uri=diagram_uri).bind(t => t.child("bodyPr"))
    let insets = ["lIns", "tIns", "rIns", "bIns"].map(name => {
      if body.bind(b => b.node.attribute(name)) is Some(value) {
        ignore(number(value, 0, 182880000))
        false
      } else {
        true
      }
    })
    output[target] = Cached(
      (insets[0], insets[1], insets[2], insets[3]),
      placeholder,
    )
  }
  output
}

///|
fn cached_font_body(
  object : Object,
  size : Double,
  insets : (Bool, Bool, Bool, Bool),
) -> Body {
  let scale = size / object.paragraphs[0].runs[0].style().size
  let body = object.body
  {
    ..body,
    left: body.left * (if insets.0 { scale } else { 1 }),
    top: body.top * (if insets.1 { scale } else { 1 }),
    right: body.right * (if insets.2 { scale } else { 1 }),
    bottom: body.bottom * (if insets.3 { scale } else { 1 }),
  }
}

///|
fn cached_font_fits(
  candidate : Object,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Bool raise @failure.Failure {
  let (body, geometry, _) = candidate.text_plane(candidate.geometry.unwrap())
  let candidate = { ..candidate, body, }
  let width = text_column_width(body, geometry.width)
  for index in 0..<candidate.paragraphs.length() {
    let (_, minimum, _) = candidate
      .paragraph_flow(index, 1)
      .content_widths(probe, profile, ligatures=false)
    if minimum > width {
      return false
    }
  }
  let (_, height) = measure_text(candidate, geometry, probe, profile, 1)
  height < geometry.height
}
