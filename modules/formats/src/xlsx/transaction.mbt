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
  media~ : Map[String, Bytes] = self.media,
  added_media~ : Map[String, Bytes] = Map([]),
  drawing_selection~ : (String, String)? = None,
  table_edits~ : Array[String] = [],
  pivot_edits~ : Array[String] = [],
  pivot_moves~ : Map[String, Range] = Map([]),
  font_context~ : (@layout.TextProbe, Map[String, String])? = self.font_context,
  fit_work~ : FitWork = {
    axes: 0,
    cells: 0,
    units: 0,
    formulas: {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: 1, column: 1, },
      names: calculation.names,
    },
  },
) -> Unit raise @failure.Failure {
  let parts = parts.copy()
  let removed_parts = self.removed.copy()
  for name in removed.keys() {
    if self.opc.names.contains(name.to_lower()) {
      removed_parts.push(name)
    }
  }
  let context = { ..self, removed: removed_parts, }
  self.maintain_pivots(
    sheets, calculation, parts, edits, pivot_edits, pivot_moves,
  )
  context.maintain_charts(sheets, workbook, calculation, parts, edits, media)
  self.protect_table_cells(sheets, calculation.names.tables, edited=table_edits)
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Workbook revision exhausted")
  }
  let styles = self.styles_from_parts(parts)
  ignore(self.font_keys(styles~, tables=calculation.names.tables, parts~))
  guard sheets.all(sheet => {
    sheet.cells.values().all(cell => cell.style < styles.length())
  }) else {
    @failure.reject("malformed-xlsx", "Cell style is outside candidate styles")
  }
  context.reflow_dimensions(
    sheets, calculation, styles, edits, font_context, fit_work, parts,
  )
  let drawings = { ..context, workbook, media, calculation: Some(calculation), }
  drawings.reflow_pictures(sheets, parts, edits, font_context)
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
    added_media
    .values()
    .fold(init=0L, (sum, bytes) => sum + bytes.length().to_int64()) +
    removed
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    })
  guard payload <= 4194304 else {
    @failure.reject("limit-exceeded", "Edit exceeds history payload budget")
  }
  self.validate(sheets, workbook~, parts~, removed=removed_parts, media~)
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
    added_media,
    bytes: payload.to_int(),
    before: self.selection,
    after,
    before_picture: self.drawing_selection,
    after_picture: drawing_selection,
  }
  while self.history.length() >= 100 ||
        entry.bytes > 4194304 - self.history_bytes {
    self.history_bytes -= self.history.remove(0).bytes
  }
  self.history.push(entry)
  self.history_bytes += entry.bytes
  self.workbook = workbook
  self.parts = parts
  self.media = media
  self.removed = removed_parts
  self.sheets = sheets
  self.styles = styles
  self.calculation = Some(calculation)
  self.font_context = font_context
  self.selection = after
  self.drawing_selection = drawing_selection
  self.anchor = { row: after.1.top, column: after.1.left, }
  self.focus = { row: after.1.bottom, column: after.1.right, }
  self.grid = None
  self.revision += 1
}
