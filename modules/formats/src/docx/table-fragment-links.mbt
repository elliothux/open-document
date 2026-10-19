///|
let table_fragment_uri = "urn:open-document:table-fragment"

///|
fn fragment_link_opening(
  tree : WordTree,
  id : Int,
  links : Map[String, @opc.Relationship],
  bookmarks : Map[String, Bool],
) -> String raise @failure.Failure {
  tree.check_hyperlink(id)
  guard !tree.children[id].is_empty() &&
    tree.children[id].all(child => {
      tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r"
    }) else {
    @failure.reject(
      "protected-content", "Rich hyperlink copies require ordinary text runs without identities",
    )
  }
  let target = hyperlink_target(tree, tree.children[id][0], links, bookmarks).unwrap()
  let output = StringBuilder()
  output.write_string(
    "<od:hyperlink xmlns:odClip=\"\{table_fragment_uri}\" odClip:target=\"\{property_attribute(target)}\"",
  )
  for name in ["history", "tooltip", "tgtFrame"] {
    if tree.nodes[id].attribute(name, uri=word_uri) is Some(value) {
      output.write_string(" od:\{name}=\"\{property_attribute(value)}\"")
    }
  }
  output.write_string(">")
  output.to_string()
}

///|
fn Session::import_fragment_links(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let targets : Map[Int, String] = Map([])
  let external : Array[String] = []
  let bookmarks = WordTree::new(self.document()).bookmark_targets()
  for node in document.nodes() {
    if node.uri != word_uri || node.name != "hyperlink" {
      continue
    }
    guard targets.length() < 4096 else {
      @failure.reject("limit-exceeded", "Rich table hyperlinks exceed 4096")
    }
    guard !node.empty &&
      !tree.children[node.id].is_empty() &&
      tree.children[node.id].all(child => {
        tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r"
      }) &&
      node.attributes.all(a => {
        (a.uri == table_fragment_uri && a.name == "target") ||
        (
          a.uri == word_uri &&
          ["history", "tooltip", "tgtFrame"].contains(a.name)
        )
      }) &&
      node.attribute("target", uri=table_fragment_uri) is Some(target) else {
      @failure.reject(
        "protected-content", "Rich hyperlink requires a portable target without source identities",
      )
    }
    check_hyperlink_target(target)
    if target.has_prefix("#") {
      guard bookmarks.contains(target[1:].to_owned().to_lower()) else {
        @failure.reject(
          "protected-content", "Copied hyperlink bookmark is missing in the receiving document",
        )
      }
    } else {
      external.push(target)
    }
    targets[node.id] = target
  }
  if targets.is_empty() {
    return document
  }
  let links = self.ensure_hyperlink_relationships(
    external,
    self.hyperlink_relationships(),
    parts,
    edits,
    created,
  )
  let changes : Array[@xml.SourceChange] = []
  for id, target in targets {
    let node = tree.nodes[id]
    let (opening, _) = hyperlink_opening(
      tree,
      document,
      Some(id),
      if target.has_prefix("#") {
        target
      } else {
        links[target]
      },
      0,
    )
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.opening_end - node.start,
      xml: opening,
    })
  }
  document.edit_source(changes).0
}
