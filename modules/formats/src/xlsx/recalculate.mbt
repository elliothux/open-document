///|
/// Recalculate workbook formulas and chart caches as one undoable edit.
pub fn Session::recalculate(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  let sheets = self.sheets.copy()
  let calculation = self.calculate(sheets, None, [], self.workbook, force=true)
  let edits = self.cache_edits(sheets, calculation)
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    self.selection,
    recalculate=true,
  )
  self.query()
}
