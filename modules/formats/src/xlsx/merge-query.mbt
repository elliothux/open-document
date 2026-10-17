///|
fn Sheet::merge_target(self : Sheet, range : Range) -> Range {
  if range.top == range.bottom && range.left == range.right {
    self.cell_range({ row: range.top, column: range.left, })
  } else {
    range
  }
}

///|
fn check_merge_markup(tree : Tree) -> Unit raise @failure.Failure {
  if tree.one(tree.root("worksheet").id, "mergeCells") is Some(container) {
    guard container.attributes
      .iter()
      .all(attribute => attribute.uri.is_empty() && attribute.name == "count") &&
      tree.children
      .get(container.id)
      .unwrap_or([])
      .all(node => {
        node.uri == spreadsheet_uri &&
        node.name == "mergeCell" &&
        node.attributes
        .iter()
        .all(attribute => attribute.uri.is_empty() && attribute.name == "ref") &&
        tree.children.get(node.id).unwrap_or([]).is_empty()
      }) else {
      @failure.reject(
        "protected-content", "Unknown merge metadata requires merge editing support",
      )
    }
  }
}

///|
fn Session::unmerge_reason(
  self : Session,
  sheet : Sheet,
  target : Range,
) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  if sheet.locked {
    return "Worksheet is protected"
  }
  if (target.bottom - target.top + 1).to_int64() *
    (target.right - target.left + 1).to_int64() >
    4096L {
    return "Merge editing exceeds 4096 cells"
  }
  try {
    check_merge_markup(Tree::new(sheet.document))
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::merge_reason(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> String {
  let reason = self.unmerge_reason(sheet, range)
  if !reason.is_empty() {
    return reason
  }
  let reason = self.format_reason(sheet, range)
  if !reason.is_empty() {
    return reason
  }
  if range.top == range.bottom && range.left == range.right {
    return "Select two or more cells to merge"
  }
  try {
    let tree = Tree::new(sheet.document)
    // shortcut: Non-anchor links and table cells need ownership support before merging.
    for node in tree.children.get(tree.root("worksheet").id).unwrap_or([]) {
      if node.uri != spreadsheet_uri ||
        (
          ["extLst", "tableParts", "pivotTableParts"].contains(node.name) &&
          !tree.children.get(node.id).unwrap_or([]).is_empty()
        ) {
        return "Worksheet resources require merge editing support"
      }
      if node.name == "hyperlinks" {
        for link in tree.all(node.id, "hyperlink") {
          let linked = Range::parse(link.attribute("ref").unwrap_or(""))
          if linked.intersects(range) &&
            !(linked.top == range.top &&
            linked.bottom == range.top &&
            linked.left == range.left &&
            linked.right == range.left) {
            return "Non-anchor hyperlinks require merge ownership support"
          }
        }
      }
    }
    ignore(self.read_sheet_notes(sheet))
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Sheet::merge_discarded(self : Sheet, target : Range) -> Int {
  self.cells
  .values()
  .fold(init=0, (count, cell) => {
    if target.contains(cell.address) &&
      !(cell.address.row == target.top && cell.address.column == target.left) &&
      (cell.value != Blank || cell.formula is Some(_)) {
      count + 1
    } else {
      count
    }
  })
}

///|
fn Session::merging(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> Json raise @failure.Failure {
  let target = sheet.merge_target(range)
  let notes = self.read_sheet_notes(sheet) catch {
    @failure.Failure(..) => None
  }
  {
    "range": target.name(),
    "merged": sheet.merges.any(merge => merge.intersects(target)),
    "discarded": sheet.merge_discarded(target),
    "discardedNotes": notes.map(n => n.merge_discarded(target)).unwrap_or(0),
    "mergeReason": self.merge_reason(sheet, target),
    "unmergeReason": self.unmerge_reason(sheet, target),
  }
}
