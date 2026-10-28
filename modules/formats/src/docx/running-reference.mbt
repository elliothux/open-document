///|
fn WordTree::running_reference_change(
  self : WordTree,
  section : Int32,
  kind : String,
  variant : String,
  relationship : String,
) -> @xml.SourceChange raise @failure.Failure {
  let node = self.nodes[section]
  let markup = "<w:\{kind}Reference xmlns:w=\"\{word_uri}\" xmlns:r=\"\{running_rel_uri}\" w:type=\"\{variant}\" r:id=\"\{property_attribute(relationship)}\"/>"
  let previous = self.children[section]
    .filter(id => {
      self.nodes[id].name == "headerReference" ||
      (kind == "footer" && self.nodes[id].name == "footerReference")
    })
    .last()
  if node.empty {
    {
      node: section,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{markup}</\{node.qualified}>",
    }
  } else {
    {
      node: section,
      offset: previous.map(id => self.nodes[id].end).unwrap_or(node.opening_end) -
      node.start,
      length: 0,
      xml: markup,
    }
  }
}
