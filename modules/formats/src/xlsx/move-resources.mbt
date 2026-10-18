///|
fn Session::check_move_resources(self : Session) -> Unit raise @failure.Failure {
  let reason = self.sheet_rename_reason(structure=false)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let mut units = self.workbook.source().length().to_int64()
  for sheet in self.sheets {
    let tree = Tree::new(sheet.document)
    // shortcut: Rule ownership and reference contexts need a joint move plan before moving ruled workbooks.
    for node in tree.children.get(tree.root("worksheet").id).unwrap_or([]) {
      guard ![
        "conditionalFormatting", "dataValidations", "autoFilter", "sortState",
      ].contains(node.name) else {
        @failure.reject(
          "protected-content", "Worksheet rules require reference-aware move support",
        )
      }
    }
    for cell in sheet.cells.values() {
      units += cell.formula.map(f => f.length().to_int64()).unwrap_or(0L)
    }
    for node in tree.document.nodes() {
      if node.name == "hyperlink" {
        units += (node.end - node.start).to_int64()
      }
    }
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Move reference work exceeds budget")
    }
  }
}
