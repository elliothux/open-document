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
      "splitTable" => @docx.SplitTable
      "headerRows" => @docx.HeaderRows(field_int(fields, "value"))
      "cellFill" => {
        let color = match fields {
          { "value": Null, .. } => None
          { "value": String(value), .. } => Some(value)
          _ =>
            @failure.reject(
              "invalid-operation", "Cell fill requires a color or null",
            )
        }
        @docx.CellFill(color)
      }
      "cellVerticalAlign" => {
        let value = match fields {
          { "value": Null, .. } => None
          { "value": String(value), .. } => Some(value)
          _ =>
            @failure.reject(
              "invalid-operation", "Cell vertical alignment requires a value or null",
            )
        }
        @docx.CellVerticalAlign(value)
      }
      "tableAlign" => @docx.TableAlign(field_string(fields, "value"))
      "cellMargins" | "tableMargins" as action => {
        let value = match fields {
          { "value": Null, .. } => None
          {
            "value": {
              "top": Number(top, ..),
              "right": Number(right, ..),
              "bottom": Number(bottom, ..),
              "left": Number(left, ..),
              ..
            },
            ..
          } => Some(@layout.CellMargins::{ top, right, bottom, left, })
          _ =>
            @failure.reject(
              "invalid-operation", "Cell margins require four numbers or null",
            )
        }
        if action == "tableMargins" {
          @docx.TableMargins(value)
        } else {
          @docx.CellMargins(value)
        }
      }
      "tableWidth" | "rowHeight" as action => {
        guard fields is { "value": Number(value, ..), .. } else {
          @failure.reject("invalid-operation", "Table size number is required")
        }
        if action == "tableWidth" {
          @docx.TableWidth(value)
        } else {
          @docx.RowHeight(value)
        }
      }
      _ => @failure.reject("invalid-operation", "Unknown table edit")
    }
    session.edit_table(revision, selection, change)
  }
  self.layout = None
  result
}
