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
    guard request is { "change": fields, .. } else {
      @failure.reject("invalid-operation", "Table edit is required")
    }
    let change = match field_string(fields, "action") {
      "rowBefore" => @docx.RowBefore
      "rowAfter" => @docx.RowAfter
      "deleteRow" => @docx.DeleteRow
      "columnBefore" => @docx.ColumnBefore
      "columnAfter" => @docx.ColumnAfter
      "deleteColumn" => @docx.DeleteColumn
      "merge" =>
        @docx.MergeCells(
          field_int(fields, "rows"),
          field_int(fields, "columns"),
        )
      "unmerge" => @docx.UnmergeCell
      _ => @failure.reject("invalid-operation", "Unknown table edit")
    }
    session.edit_table(revision, selection, change)
  }
  self.layout = None
  result
}
