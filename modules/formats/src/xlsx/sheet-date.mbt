///|
/// Uses the supplied calendar date for this and subsequent operations; failures restore it.
pub fn Session::edit_sheet(
  self : Session,
  revision : Int,
  sheet : String,
  change : SheetEdit,
  date~ : String? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let previous = self.calendar_date
  if date is Some(date) {
    self.calendar_date = Some(filter_current_date(date))
  }
  errdefer {
    self.calendar_date = previous
  }
  let result = self.edit_sheet_current(revision, sheet, change)
  if self.calendar_date != previous {
    self.grid = None
  }
  result
}
