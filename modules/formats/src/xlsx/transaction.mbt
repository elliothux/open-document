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
) -> Unit raise @failure.Failure {
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Workbook revision exhausted")
  }
  let payload = edits
    .iter()
    .fold(init=0L, (sum, entry) => sum + entry.1.payload_bytes()) +
    created
    .map(sheet => sheet.document.source().length().to_int64() * 2)
    .unwrap_or(0L)
  guard payload <= 4194304 else {
    @failure.reject("limit-exceeded", "Edit exceeds history payload budget")
  }
  self.validate(sheets, workbook~, parts~)
  for item in self.redo {
    self.history_bytes -= item.bytes
  }
  self.redo.clear()
  let entry : History = {
    edits,
    created,
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
  self.sheets = sheets
  self.calculation = Some(calculation)
  self.selection = after
  self.anchor = { row: after.1.top, column: after.1.left, }
  self.focus = { row: after.1.bottom, column: after.1.right, }
  self.grid = None
  self.revision += 1
}
