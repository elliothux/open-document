///|
fn Session::fragment_math_nodes(
  self : Session,
  document : @xml.Document,
  objects : Map[Int32, Bool],
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  let roots = tree.order.filter(id => tree.math_root(id))
  guard roots.length() <= 256 else {
    @failure.reject("limit-exceeded", "Rich math expressions exceed 256")
  }
  for id in roots {
    ignore(self.math_target(tree, id))
    for node in tree.descendants(id) {
      objects[node] = true
    }
  }
}
