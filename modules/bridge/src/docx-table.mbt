///|
fn Foundation::docx_table(
  self : Foundation,
  session : @docx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  let selection = field_selection(request)
  let result = if operation == "insertDocxTable" {
    session.insert_table(
      revision,
      selection,
      field_int(request, "rows"),
      field_int(request, "columns"),
    )
  } else {
    let change = match field_string(request, "change") {
      "rowBefore" => @docx.RowBefore
      "rowAfter" => @docx.RowAfter
      "deleteRow" => @docx.DeleteRow
      "columnBefore" => @docx.ColumnBefore
      "columnAfter" => @docx.ColumnAfter
      "deleteColumn" => @docx.DeleteColumn
      _ => @failure.reject("invalid-operation", "Unknown table edit")
    }
    session.edit_table(revision, selection, change)
  }
  self.layout = None
  result
}
