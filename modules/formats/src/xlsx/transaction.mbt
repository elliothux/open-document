///|
fn Session::commit(
  self : Session,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  calculation : Calculation,
  edits : Array[(String, @xml.Edit)],
  after : (String, Range),
  parts~ : Map[String, @xml.Document] = self.parts,
  created~ : Sheet? = None,
  created_parts~ : Map[String, @xml.Document] = Map([]),
  deleted~ : Sheet? = None,
  removed~ : Map[String, @xml.Document] = Map([]),
  font_context~ : (@layout.TextProbe, Map[String, String])? = self.font_context,
  fit_work~ : FitWork = { axes: 0, cells: 0, units: 0, },
) -> Unit raise @failure.Failure {
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Workbook revision exhausted")
  }
  let styles = self.styles_from_parts(parts)
  guard sheets.all(sheet => {
    sheet.cells.values().all(cell => cell.style < styles.length())
  }) else {
    @failure.reject("malformed-xlsx", "Cell style is outside candidate styles")
  }
  self.reflow_dimensions(
    sheets, calculation, styles, edits, font_context, fit_work,
  )
  let payload = edits
    .iter()
    .fold(init=0L, (sum, entry) => sum + entry.1.payload_bytes()) +
    created
    .map(sheet => sheet.document.source().length().to_int64() * 2)
    .unwrap_or(0L) +
    created_parts
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    }) +
    removed
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    })
  guard payload <= 4194304 else {
    @failure.reject("limit-exceeded", "Edit exceeds history payload budget")
  }
  let removed_parts = self.removed.copy()
  for name in removed.keys() {
    if self.opc.names.contains(name.to_lower()) {
      removed_parts.push(name)
    }
  }
  self.validate(sheets, workbook~, parts~, removed=removed_parts)
  for item in self.redo {
    self.history_bytes -= item.bytes
  }
  self.redo.clear()
  let entry : History = {
    edits,
    created,
    created_parts,
    deleted,
    removed,
    bytes: payload.to_int(),
    before: self.selection,
    after,
  }
  while self.history.length() >= 100 ||
        entry.bytes > 4194304 - self.history_bytes {
    self.history_bytes -= self.history.remove(0).bytes
  }
  self.history.push(entry)
  self.history_bytes += entry.bytes
  self.workbook = workbook
  self.parts = parts
  self.removed = removed_parts
  self.sheets = sheets
  self.styles = styles
  self.calculation = Some(calculation)
  self.font_context = font_context
  self.selection = after
  self.anchor = { row: after.1.top, column: after.1.left, }
  self.focus = { row: after.1.bottom, column: after.1.right, }
  self.grid = None
  self.revision += 1
}
