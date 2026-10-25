///|
fn Session::markup_fields(
  self : Session,
  tree : WordTree,
  layout : @layout.Layout?,
) -> Map[Int, String] raise @failure.Failure {
  let fields = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri &&
    tree.nodes[id].name == "fldSimple" &&
    !tree.index_markers.contains(id)
  })
  let values = self.field_values(tree, fields, layout)
  Map::from_array(
    fields.map(id => {
      (tree.child(tree.field_result_run(id).unwrap(), "t").unwrap(), values[id])
    }),
  )
}
