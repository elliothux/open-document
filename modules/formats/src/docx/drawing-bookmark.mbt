///|
fn Session::edit_drawing_bookmark_links(
  self : Session,
  tree : WordTree,
  name : String,
  replacement : String?,
  changes : Array[@xml.SourceChange],
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  affected : Array[Int],
) -> Unit raise @failure.Failure {
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let owners : Map[String, Map[String, @opc.Relationship]] = Map([])
  for relation in self.relationships() {
    if relation.external &&
      relation.kind == rel_uri + "/hyperlink" &&
      relation.target.to_lower() == "#" + name.to_lower() {
      owners.get_or_init(relation.owner, () => Map([]))[relation.id] = relation
    }
  }
  let mut work = 0
  for owner, relations in owners {
    guard owner.to_lower().has_suffix(".xml") else {
      @failure.reject(
        "protected-content", "Bookmark relationship owner requires editing support",
      )
    }
    let source = if owner == self.main {
      tree
    } else {
      WordTree::new(self.part_xml(owner))
    }
    let references : Array[@xml.Node] = []
    for id in source.order {
      let node = source.nodes[id]
      work += node.attributes.length() + 1
      guard work <= 8388608 else {
        @failure.reject(
          "limit-exceeded", "Drawing bookmark references exceed the work budget",
        )
      }
      if node.attributes.any(a => {
          a.uri == rel_uri && relations.contains(a.value)
        }) {
        references.push(node)
      }
    }
    guard references.length() <= 65536 else {
      @failure.reject(
        "limit-exceeded", "Drawing bookmark references exceed the work budget",
      )
    }
    if references.is_empty() {
      continue
    }
    guard owner == self.main else {
      @failure.reject(
        "protected-content", "Bookmark relationships in other document parts require editing support",
      )
    }
    let used : Set[String] = Set([])
    for node in references {
      guard node.uri == picture_drawing_uri &&
        node.name == "hlinkClick" &&
        tree.nodes.get(node.parent) is Some(identity) &&
        identity.uri == picture_inline_uri &&
        identity.name == "docPr" &&
        tree.nodes
        .get(identity.parent)
        .bind(frame => tree.nodes.get(frame.parent))
        is Some(drawing) else {
        @failure.reject(
          "protected-content", "Unknown bookmark relationship reference requires editing support",
        )
      }
      let paragraph = self.editable_drawing_link(tree, drawing.id)
      guard tree.drawing_link_node(drawing.id).1 == Some(node.id) else {
        @failure.reject(
          "protected-content", "Unknown drawing bookmark link owner",
        )
      }
      used.add(node.attribute("id", uri=rel_uri).unwrap())
      affected.push(paragraph)
      if replacement is None {
        changes.push({
          node: identity.id,
          offset: node.start - identity.start,
          length: node.end - node.start,
          xml: "",
        })
      }
    }
    if replacement is Some(replacement) {
      let path = running_rels_path(owner)
      let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
      let document = parts.get(path).unwrap_or_else(() => self.part_xml(path))
      let updates : Array[@xml.SourceChange] = []
      for node in document.nodes() {
        if used.contains(node.attribute("Id").unwrap_or("")) {
          let attr = node.attributes
            .iter()
            .find_first(a => a.uri.is_empty() && a.name == "Target")
            .unwrap()
          updates.push({
            node: node.id,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: property_attribute("#" + replacement),
          })
        }
      }
      guard updates.length() == used.length() else {
        @failure.reject(
          "protected-content", "Incomplete drawing bookmark relationships",
        )
      }
      let (candidate, edit) = document.edit_source(updates)
      parts[path] = candidate
      edits.get_or_init(path, () => []).push(edit)
    }
  }
}
