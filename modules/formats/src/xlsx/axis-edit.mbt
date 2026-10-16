///|
fn Session::edit_axes(
  self : Session,
  id : String,
  change : AxisChange,
) -> Json raise @failure.Failure {
  guard change.first >= 1 &&
    change.first <= change.limit() &&
    change.count >= 1 &&
    change.count <= 4096 &&
    change.count <= change.limit() - change.first + 1 else {
    @failure.reject(
      "invalid-operation", "Invalid structural row or column interval",
    )
  }
  let index = self.sheet_index(id)
  let reason = self.sheet_rename_reason(structure=false)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let target = self.sheets[index]
  guard !target.locked && target.frozen.edit_reason.is_empty() else {
    @failure.reject(
      "protected-content", "Protected worksheet or view prevents structural editing",
    )
  }
  for relation in self.relationships() {
    if relation.owner == id && relation.kind != relationship_uri + "hyperlink" {
      @failure.reject(
        "protected-content", "Worksheet resources require reference-aware structural editing",
      )
    }
  }
  let tree = Tree::new(target.document)
  for node in tree.children.get(tree.root("worksheet").id).unwrap_or([]) {
    guard [
      "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
      "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
      "headerFooter", "conditionalFormatting", "dataValidations", "hyperlinks", "extLst",
    ].contains(node.name) else {
      @failure.reject(
        "protected-content", "Worksheet metadata requires structural range support",
      )
    }
  }
  let sheets = self.sheets.copy()
  let edits : Array[(String, @xml.Edit)] = []
  for i, original in sheets {
    if change.band is Some(_) {
      guard !original.document
        .nodes()
        .any(n => {
          n.uri == spreadsheet_uri &&
          ["conditionalFormatting", "dataValidation"].contains(n.name)
        }) else {
        @failure.reject(
          "protected-content", "Cell shifts require per-cell conditional format and validation transformations",
        )
      }
    }
    let updates : Map[String, CellContent] = Map([])
    let source = Tree::new(original.document)
    for name, cell in original.cells {
      if cell.formula is Some(formula) {
        let text = axis_formula(
          formula,
          Some(original.name),
          target.name,
          change,
        )
        let moved = original.id == id &&
          change.address(cell.address) != Some(cell.address)
        if text != formula || (moved && cell.group is Some(_)) {
          updates[name] = {
            value: cell.value,
            formula: Some(text),
            keep_shared: false,
          }
        }
      }
    }
    let mut document = original.document
    if !updates.is_empty() {
      original.expand_shared_updates(updates)
      for name in updates.keys() {
        let node = source.one(original.cells[name].node, "f").unwrap()
        guard source.children.get(node.id).unwrap_or([]).is_empty() &&
          node.attributes.all(a => {
            a.uri.is_empty() && ["t", "ref", "si"].contains(a.name)
          }) &&
          !original.document.source()[node.opening_end:node.closing_start].contains(
            "<",
          ) else {
          @failure.reject(
            "protected-content", "Unknown shared formula metadata prevents structural editing",
          )
        }
      }
      let (next, edit) = original.prepare(updates)
      document = next
      edits.push((original.id, edit))
    }
    let current = Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
    let metadata = axis_sheet_metadata(current, target.name, change)
    if !metadata.is_empty() {
      let (next, edit) = document.edit_source(metadata)
      document = next
      edits.push((original.id, edit))
    }
    if original.id == id {
      let current = Sheet::read(
        original.id,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
      let changes = if change.band is Some(_) {
        current.shift_cells(change, self.budget.entry_bytes.min(4194304))
      } else {
        current.axis_cells(change)
      }
      if !changes.is_empty() {
        let (next, edit) = document.edit_source(changes)
        document = next
        edits.push((id, edit))
      }
    }
    sheets[i] = Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
  }
  let mut workbook = self.workbook
  let names = self.axis_names(target.name, change)
  if !names.is_empty() {
    let (next, edit) = workbook.edit_source(names)
    workbook = next
    edits.push((self.main, edit))
  }
  let after = if change.band is Some((first, last)) {
    (
      id,
      if change.rows {
        {
          top: change.first,
          bottom: change.first + change.count - 1,
          left: first,
          right: last,
        }
      } else {
        {
          top: first,
          bottom: last,
          left: change.first,
          right: change.first + change.count - 1,
        }
      },
    )
  } else if self.selection.0 == id {
    let selected = self.selection.1
    let range = change
      .range(selected)
      .unwrap_or_else(() => {
        let point = change.position({
          row: selected.top,
          column: selected.left,
        })
        {
          top: point.row,
          bottom: point.row,
          left: point.column,
          right: point.column,
        }
      })
    (id, range)
  } else {
    self.selection
  }
  if edits.is_empty() {
    return self.query()
  }
  let calculation = Calculation::build(sheets, None, [], self.date1904)
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(sheets, workbook, calculation, edits, after)
  self.query()
}
