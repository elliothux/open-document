///|
fn drawing_click_markup(
  node : @xml.Node,
  target : String,
  portable~ : Bool,
) -> String raise @failure.Failure {
  let reference = if portable {
    " xmlns:odClip=\"\{table_fragment_uri}\" odClip:target"
  } else {
    " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id"
  }
  let markup = StringBuilder()
  markup.write_string(
    "<a:hlinkClick xmlns:a=\"\{picture_drawing_uri}\"" +
    reference +
    "=\"\{property_attribute(target)}\"",
  )
  for attr in node.attributes {
    if attr.uri.is_empty() {
      markup.write_string(" \{attr.name}=\"\{property_attribute(attr.value)}\"")
    }
  }
  markup.write_string("/>")
  markup.to_string()
}

///|
fn Session::export_fragment_drawing_link(
  self : Session,
  document : @xml.Document,
  drawing : Int32,
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  guard self.drawing_link_target(tree, drawing) is Some(target) else {
    return document
  }
  let node = tree.nodes[tree.drawing_link_node(drawing).1.unwrap()]
  document.edit_source([
    {
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: drawing_click_markup(node, target, portable=true),
    },
  ]).0
}

///|
fn WordTree::fragment_drawing_link_target(
  self : WordTree,
  id : Int32,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  guard self.nodes.get(node.parent) is Some(identity) &&
    identity.uri == picture_inline_uri &&
    identity.name == "docPr" &&
    self.nodes.get(identity.parent).bind(frame => self.nodes.get(frame.parent))
    is Some(drawing) &&
    drawing.uri == word_uri &&
    drawing.name == "drawing" &&
    self.drawing_link_node(drawing.id, portable=true).1 == Some(id) &&
    [
      Some(word_shape_uri),
      Some("http://schemas.openxmlformats.org/drawingml/2006/picture"),
    ].contains(self.drawing_data(drawing.id).1.attribute("uri")) else {
    @failure.reject(
      "protected-content", "Copied drawing hyperlink requires a portable native click target",
    )
  }
  let target = node.attribute("target", uri=table_fragment_uri).unwrap()
  check_hyperlink_target(target)
  target
}

///|
fn Session::import_fragment_drawing_links(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let targets : Map[Int32, String] = Map([])
  let addresses : Array[String] = []
  for node in document.nodes() {
    if node.uri != picture_drawing_uri || node.name != "hlinkClick" {
      continue
    }
    guard targets.length() < 256 else {
      @failure.reject("limit-exceeded", "Copied drawing hyperlinks exceed 256")
    }
    let target = tree.fragment_drawing_link_target(node.id)
    targets[node.id] = target
    addresses.push(target)
  }
  if targets.is_empty() {
    return document
  }
  let view = { ..self, parts, }
  let links = view.ensure_hyperlink_relationships(
    self.main,
    addresses,
    view.hyperlink_relationships(),
    parts,
    edits,
    created,
  )
  let changes : Array[@xml.SourceChange] = []
  for id, target in targets {
    let node = tree.nodes[id]
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: drawing_click_markup(node, links[target], portable=false),
    })
  }
  document.edit_source(changes).0
}
