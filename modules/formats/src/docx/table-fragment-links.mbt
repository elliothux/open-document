///|
let table_fragment_uri = "urn:open-document:table-fragment"

///|
fn fragment_link_opening(
  tree : WordTree,
  id : Int32,
  links : Map[String, @opc.Relationship],
  bookmarks : Map[String, Bool],
) -> String raise @failure.Failure {
  tree.check_hyperlink(id)
  guard !tree.children[id].is_empty() &&
    tree.children[id].all(child => {
      tree.is_bookmark(child) ||
      (tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r")
    }) else {
    @failure.reject(
      "protected-content", "Rich hyperlink copies require ordinary text runs without identities",
    )
  }
  let run = tree.children[id]
    .iter()
    .find_first(child => {
      tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r"
    })
    .unwrap_or_else(() => {
      @failure.reject(
        "protected-content", "Rich hyperlinks require ordinary text runs",
      )
    })
  let target = hyperlink_target(tree, run, links, bookmarks).unwrap()
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
fn fragment_link_target(
  tree : WordTree,
  node : @xml.Node,
) -> String raise @failure.Failure {
  guard !node.empty &&
    tree.children[node.id].any(child => {
      tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r"
    }) &&
    tree.children[node.id].all(child => {
      tree.is_bookmark(child) ||
      (tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r")
    }) &&
    node.attributes.all(a => {
      (a.uri == table_fragment_uri && a.name == "target") ||
      (a.uri == word_uri && ["history", "tooltip", "tgtFrame"].contains(a.name))
    }) &&
    node.attribute("target", uri=table_fragment_uri) is Some(target) else {
    @failure.reject(
      "protected-content", "Rich hyperlink requires a portable target without source identities",
    )
  }
  check_hyperlink_target(target)
  target
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
  let targets : Map[Int32, String] = Map([])
  let external : Array[String] = []
  for node in document.nodes() {
    if node.uri != word_uri || node.name != "hyperlink" {
      continue
    }
    guard targets.length() < 4096 else {
      @failure.reject("limit-exceeded", "Rich table hyperlinks exceed 4096")
    }
    let target = fragment_link_target(tree, node)
    if !target.has_prefix("#") {
      external.push(target)
    }
    targets[node.id] = target
  }
  if targets.is_empty() {
    return document
  }
  let links = self.ensure_hyperlink_relationships(
    self.main,
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
