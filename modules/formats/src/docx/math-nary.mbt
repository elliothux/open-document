///|
fn Session::math_nary_limit(
  self : Session,
  operator : String,
) -> String raise @failure.Failure {
  let integral = "∫∬∭∮∯∰".contains(operator)
  let name = if integral { "intLim" } else { "naryLim" }
  let mut result = if integral { "subSup" } else { "undOvr" }
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let seen : Set[String] = Set([])
    for id in tree.order {
      let node = tree.nodes[id]
      if node.uri != math_uri || node.name != name {
        continue
      }
      guard !seen.contains(node.name) &&
        node.attributes.length() == 1 &&
        tree.children[id].is_empty() &&
        node.text.trim().is_empty() &&
        node.attribute("val", uri=math_uri) is Some(value) &&
        ["subSup", "undOvr"].contains(value) else {
        @failure.reject(
          "unsupported-math", "Invalid or repeated n-ary limit setting",
        )
      }
      seen.add(node.name)
      result = value
    }
  }
  result
}
