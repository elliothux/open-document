///|
fn Session::move_hyperlinks(
  self : Session,
  sheet : Sheet,
  document : @xml.Document,
  source : Sheet,
  target : Sheet,
  relocation : CellMove,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = Tree::new(document)
  let changes : Array[@xml.SourceChange] = []
  let nodes = hyperlink_nodes(tree)
  let mut count = nodes.length()
  let mut units = 0
  for node in nodes {
    let range = Range::parse(node.attribute("ref").unwrap_or(""))
    if sheet.id == source.id && range.intersects(relocation.source) {
      guard relocation.source.covers(range) else {
        @failure.reject(
          "protected-content", "Move must contain complete source hyperlinks",
        )
      }
      hyperlink_source(tree, node)
      changes.push(sheet_node_removal(tree, node))
      count -= 1
      continue
    }
    let pieces = if sheet.id == target.id {
      range.without(relocation.target)
    } else {
      [range]
    }
    let location = node.attribute("location")
    let next = location.map(text => {
      move_formula(text, relocation, Some(sheet.name), Some(sheet.name))
    })
    if pieces == [range] && location == next {
      continue
    }
    hyperlink_source(tree, node)
    let xml = pieces
      .map(piece => {
        hyperlink_fragment(
          tree,
          node,
          piece,
          next.map(text => "#" + text),
          None,
        )
      })
      .join("")
    units += xml.length()
    count += pieces.length() - 1
    guard count <= 4096 && units <= 2097152 else {
      @failure.reject("limit-exceeded", "Moved hyperlinks exceed source budget")
    }
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml,
    })
  }
  if sheet.id == target.id {
    let before = Tree::new(source.document)
    let relations = self.hyperlink_relations(source.id)
    let additions = StringBuilder()
    for node in hyperlink_nodes(before) {
      let range = Range::parse(node.attribute("ref").unwrap_or(""))
      if !range.intersects(relocation.source) {
        continue
      }
      guard relocation.source.covers(range) else {
        @failure.reject(
          "protected-content", "Move must contain complete source hyperlinks",
        )
      }
      let link = hyperlink_target(before, node, relations)
      let link = if link.has_prefix("#") {
        "#" +
        move_formula(
          link[1:].to_owned(),
          relocation,
          Some(source.name),
          Some(target.name),
        )
      } else {
        link
      }
      let relation = if link.has_prefix("#") {
        None
      } else {
        Some(self.hyperlink_relation(target, link, parts, edits, created))
      }
      // The existing fragment helper makes inherited source namespace bindings local.
      let fragment = style_fragment(before, node)
      let xml = hyperlink_fragment(
        Tree::new(fragment),
        fragment.nodes()[0],
        relocation.range(range),
        Some(link),
        relation,
      )
      units += xml.length()
      count += 1
      guard count <= 4096 && units <= 2097152 else {
        @failure.reject(
          "limit-exceeded", "Moved hyperlinks exceed source budget",
        )
      }
      additions.write_string(xml)
    }
    if !additions.is_empty() {
      changes.push(hyperlink_insertion(tree, additions.to_string()))
    }
  }
  if changes.is_empty() {
    return document
  }
  guard !sheet.locked else {
    @failure.reject(
      "protected-content", "A moved or dependent hyperlink is protected",
    )
  }
  let (next, edit) = document.edit_source(join_insertions(changes))
  let next_tree = Tree::new(next)
  let nodes = hyperlink_nodes(next_tree)
  let candidate = { ..self, parts, }
  let relations = candidate.hyperlink_relations(sheet.id)
  for node in nodes {
    ignore(hyperlink_target(next_tree, node, relations))
  }
  edits.push((sheet.id, edit))
  next
}
