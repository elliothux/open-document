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
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
  } else {
    guard request is { "change": fields, .. } else {
      @failure.reject("invalid-operation", "Table edit is required")
    }
    let change = match field_string(fields, "action") {
      "autoFit" => @docx.AutoFit(field_string(fields, "mode"))
      "tableBorders" | "cellBorders" as action => {
        guard fields is { "value": Object(values), .. } else {
          @failure.reject("invalid-operation", "Border patch is required")
        }
        let patch : Map[String, @layout.BorderStyle?] = Map([])
        for side, value in values {
          patch[side] = match value {
            Null => None
            { "width": Number(width, ..), "color": String(color), .. } =>
              Some({ width, color, })
            _ => @failure.reject("invalid-operation", "Invalid border patch")
          }
        }
        if action == "tableBorders" {
          @docx.TableBorders(patch)
        } else {
          @docx.CellBorders(patch)
        }
      }
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
      "splitCell" =>
        @docx.SplitCell(field_int(fields, "rows"), field_int(fields, "columns"))
      "splitTable" => @docx.SplitTable
      "pasteCells" => @docx.PasteCells(field_string(fields, "text"))
      "pasteFragment" =>
        @docx.PasteCellFragment(field_string(fields, "fragment"))
      "headerRows" => @docx.HeaderRows(field_int(fields, "value"))
      "rowSplit" =>
        @docx.RowSplit(
          match fields {
            { "value": True, .. } => true
            { "value": False, .. } => false
            _ =>
              @failure.reject(
                "invalid-operation", "Row split setting requires a boolean",
              )
          },
        )
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
      "tableWidth" | "rowHeight" | "columnWidth" as action => {
        guard fields is { "value": Number(value, ..), .. } else {
          @failure.reject("invalid-operation", "Table size number is required")
        }
        if action == "columnWidth" {
          @docx.ColumnWidth(field_int(fields, "column"), value)
        } else if action == "tableWidth" {
          @docx.TableWidth(value)
        } else {
          @docx.RowHeight(value, field_string(fields, "rule"))
        }
      }
      _ => @failure.reject("invalid-operation", "Unknown table edit")
    }
    session.edit_table(
      revision,
      selection,
      change,
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
  }
  self.layout = None
  result
}
