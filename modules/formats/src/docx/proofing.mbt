///|
fn WordTree::check_proofing_marker(
  self : WordTree,
  id : Int32,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  guard node.uri == word_uri &&
    node.name == "proofErr" &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.length() == 1 &&
    node.attributes[0].uri == word_uri &&
    node.attributes[0].name == "type" &&
    ["spellStart", "spellEnd", "gramStart", "gramEnd"].contains(
      node.attributes[0].value,
    ) else {
    @failure.reject("protected-content", "Invalid proofing range marker")
  }
}
