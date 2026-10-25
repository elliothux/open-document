///|
fn Session::set_note(
  self : Session,
  id : String,
  cell : String,
  text : String?,
  author : String,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let requested = Address::parse(cell)
  let range = sheet.merge_target({
    top: requested.row,
    bottom: requested.row,
    left: requested.column,
    right: requested.column,
  })
  let address : Address = { row: range.top, column: range.left, }
  if self.thread_part(id, "threadedComment") is Some(_) {
    guard !self.read_sheet_threads(sheet).messages.any(m => m.address == address) else {
      @failure.reject(
        "protected-content", "Use thread controls to edit this comment",
      )
    }
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  guard self.prepare_note(
      sheet,
      address,
      text,
      author,
      parts,
      created,
      edits,
      allow_threads=true,
    )
    is Some(sheet_document) else {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    sheet.name,
    sheet.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}

///|
fn check_note_author(author : String) -> Unit raise @failure.Failure {
  guard !author.trim().is_empty() &&
    author.length() <= 255 &&
    @xml.valid_text(author) &&
    author.iter().all(c => c >= ' ') else {
    @failure.reject(
      "invalid-operation", "New cell notes require an explicit bounded author",
    )
  }
}
