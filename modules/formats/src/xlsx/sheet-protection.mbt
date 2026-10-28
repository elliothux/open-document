///|
fn sheet_protection_reason(
  tree : Tree,
  root : Int32,
  selection~ : Bool = true,
) -> String {
  let nodes = tree.all(root, "sheetProtection")
  guard nodes is [node] else {
    return if nodes.is_empty() { "" } else { "Duplicate worksheet protection" }
  }
  guard tree.children
    .get(root)
    .unwrap_or([])
    .all(child => {
      child.uri == spreadsheet_uri &&
      [
        "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
        "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
        "headerFooter", "autoFilter", "sortState", "dataValidations", "conditionalFormatting",
        "hyperlinks", "legacyDrawing", "tableParts",
      ].contains(child.name)
    }) else {
    return "Protected worksheet contains unsupported metadata"
  }
  let flags = [
    "sheet", "objects", "scenarios", "formatCells", "formatColumns", "formatRows",
    "insertColumns", "insertRows", "insertHyperlinks", "deleteColumns", "deleteRows",
    "selectLockedCells", "sort", "autoFilter", "pivotTables", "selectUnlockedCells",
  ]
  guard node.text.trim().is_empty() &&
    tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        flags.contains(a.name) ||
        ["password", "algorithmName", "hashValue", "saltValue", "spinCount"].contains(
          a.name,
        )
      ) &&
      (!flags.contains(a.name) || ["0", "1", "false", "true"].contains(a.value))
    }) else {
    return "Unsupported worksheet protection metadata"
  }
  if selection &&
    ["selectLockedCells", "selectUnlockedCells"].any(name => {
      ["1", "true"].contains(node.attribute(name).unwrap_or("0"))
    }) {
    return "Worksheet selection restrictions require editing support"
  }
  ""
}

///|
fn Session::cell_edit_reason(
  self : Session,
  sheet : Sheet,
  address : Address,
) -> String raise @failure.Failure {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  if sheet.locked {
    if !sheet.protection_reason.is_empty() {
      return sheet.protection_reason
    }
    if self.styles[sheet.style_at(address)].locked {
      return "Worksheet cell is locked"
    }
  }
  if self.calculation is Some(calculation) &&
    calculation.protects(self.sheet_index(sheet.id), address) {
    return "Cell affects an uncalculated formula"
  }
  sheet.cells.get(address.name()).map(cell => cell.read_only).unwrap_or("")
}
