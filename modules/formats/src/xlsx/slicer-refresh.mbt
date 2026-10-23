///|
fn Session::rebuild_slicer_state(
  self : Session,
  cache : SlicerCache,
  settings : PivotSettings,
  data : PivotCache,
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let values = data.axis_items(cache.field)
  guard !values.is_empty() && values.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Refreshed slicer members exceed budget")
  }
  if cache.members.length() == values.length() &&
    cache.members.all(item => {
      item.index < values.length() &&
      pivot_item_key(item.value) == pivot_item_key(values[item.index])
    }) {
    self.sync_slicer_state(cache, settings, data, edits)
    return
  }
  let original = self.part_xml(cache.part)
  let tree = Tree::new(original)
  let tabular = tree.slicer_node(tree.slicer_node(0, "data").id, "tabular")
  let items = tree.slicer_node(tabular.id, "items")
  let changes = metadata_changes(items, [("count", values.length().to_string())])
  changes.push({
    node: items.id,
    offset: items.opening_end - items.start,
    length: items.closing_start - items.opening_end,
    xml: values
    .mapi((index, _) => "<i xmlns=\"\{slicer_uri}\" x=\"\{index}\" s=\"1\"/>")
    .join(""),
  })
  let (document, edit) = original.edit_source(changes)
  self.parts[cache.part] = document
  let updates = [(cache.part, edit)]
  self.sync_slicer_state(
    {
      ..cache,
      members: values.mapi((index, value) => {
        index,
        value,
        selected: true,
        hasData: true,
      }),
    },
    settings,
    data,
    updates,
  )
  if self.part_xml(cache.part).source() == original.source() {
    self.parts[cache.part] = original
  } else {
    edits.append(updates)
  }
}
