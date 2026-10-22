///|
fn Session::fragment_math_nodes(
  self : Session,
  document : @xml.Document,
  objects : Map[Int, Bool],
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  let roots = tree.order.filter(id => {
    tree.nodes[id].uri == math_uri && tree.nodes[id].name == "oMath"
  })
  guard roots.length() <= 256 else {
    @failure.reject("limit-exceeded", "Rich fractions exceed 256")
  }
  for id in roots {
    ignore(self.math_fraction_target(tree, id))
    for node in tree.descendants(id) {
      objects[node] = true
    }
  }
}
