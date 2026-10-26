///|
fn WordTree::check_row_format_properties(
  self : WordTree,
  properties : Int,
  change~ : Int? = None,
  snapshot~ : Bool = false,
) -> Unit raise @failure.Failure {
  let node = self.nodes[properties]
  let source = self.source[node.start:node.end]
  guard node.uri == word_uri &&
    node.name == "trPr" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque row properties require review support",
    )
  }
  let names : Set[String] = Set([])
  for id in self.children[properties] {
    let child = self.nodes[id]
    guard child.uri == word_uri && !names.contains(child.name) else {
      @failure.reject(
        "protected-content", "Foreign or duplicate row properties",
      )
    }
    names.add(child.name)
    if change == Some(id) {
      continue
    }
    if !snapshot && self.is_row_revision(id) {
      guard self.children[id].is_empty() &&
        child.text.trim().is_empty() &&
        child.attributes.all(a => {
          a.uri == word_uri && ["id", "author", "date"].contains(a.name)
        }) else {
        @failure.reject("protected-content", "Unknown row revision metadata")
      }
      ignore(comment_key(child.attribute("id", uri=word_uri).unwrap_or("")))
      continue
    }
    guard ["trHeight", "cantSplit", "tblHeader", "gridAfter"].contains(
        child.name,
      ) &&
      (child.name != "tblHeader" || self.valid_on_off_property(id)) else {
      @failure.reject(
        "protected-content", "Unknown row formatting requires review support",
      )
    }
  }
  ignore(self.table_row_height(node.parent))
  ignore(self.table_row_split(node.parent))
  ignore(self.row_grid_after(node.parent))
}

///|
fn WordTree::check_row_property_revision(
  self : WordTree,
  id : Int,
) -> Int raise @failure.Failure {
  let change = self.nodes[id]
  guard change.uri == word_uri &&
    change.name == "trPrChange" &&
    change.text.trim().is_empty() &&
    change.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    self.nodes.get(change.parent) is Some(properties) &&
    properties.uri == word_uri &&
    properties.name == "trPr" &&
    self.nodes.get(properties.parent) is Some(row) &&
    row.uri == word_uri &&
    row.name == "tr" &&
    self.nodes.get(row.parent) is Some(table) &&
    table.uri == word_uri &&
    table.name == "tbl" &&
    self.nodes[table.parent].uri == word_uri &&
    self.nodes[table.parent].name == "body" &&
    self.nodes[table.parent].parent == 0 &&
    self.table_children(row.id, "trPr").length() == 1 &&
    self.children[id] is [previous] else {
    @failure.reject(
      "protected-content", "Row formatting revision requires one ordinary previous property set",
    )
  }
  ignore(comment_key(change.attribute("id", uri=word_uri).unwrap_or("")))
  self.check_row_format_properties(properties.id, change=Some(id))
  self.check_row_format_properties(previous, snapshot=true)
  guard self.row_grid_after(row.id) == self.row_grid_after(id) else {
    @failure.reject(
      "protected-content", "Row grid revisions require structural review support",
    )
  }
  let cells = self.table_children(row.id, "tc")
  guard !cells.is_empty() else {
    @failure.reject("protected-content", "Revision row has no cells")
  }
  for cell in cells {
    self.check_merge_cell(cell, "", notes=true, review=true)
  }
  self.child(cells[0], "p").unwrap()
}
