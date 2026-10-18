///|
fn hyperlink_insertion(
  tree : Tree,
  additions : String,
) -> @xml.SourceChange raise @failure.Failure {
  let root = tree.root("worksheet")
  if tree.one(root.id, "hyperlinks") is Some(parent) {
    return insertion(parent, additions)
  }
  let markup = "<od:hyperlinks xmlns:od=\"\{spreadsheet_uri}\">\{additions}</od:hyperlinks>"
  let next = tree.children
    .get(root.id)
    .unwrap_or([])
    .iter()
    .find_first(n => {
      [
        "printOptions", "pageMargins", "pageSetup", "headerFooter", "rowBreaks",
        "colBreaks", "customProperties", "cellWatches", "ignoredErrors", "smartTags",
        "drawing", "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects", "controls",
        "webPublishItems", "tableParts", "extLst",
      ].contains(n.name)
    })
  if next is Some(node) {
    { node: root.id, offset: node.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
}
