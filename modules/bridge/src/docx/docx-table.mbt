///|
fn Context::docx_table(
  self : Context,
  session : @model.Session,
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
      profile=font_profile(request),
      images=self.images,
    )
  } else {
    guard request is { "change": fields, .. } else {
      @failure.reject("invalid-operation", "Table edit is required")
    }
    let change = match field_string(fields, "action") {
      "autoFit" => @model.AutoFit(field_string(fields, "mode"))
      "tableBorders" | "cellBorders" as action => {
        guard fields is { "value": Object(values), .. } else {
          @failure.reject("invalid-operation", "Border patch is required")
        }
        let patch : Map[String, @model.TableBorderStyle?] = Map([])
        for side, value in values {
          patch[side] = match value {
            Null => None
            {
              "style": String(style),
              "width": Number(width, ..),
              "color": String(color),
              ..
            } => {
              guard value is Object(properties) &&
                properties
                .keys()
                .all(key => {
                  ["style", "width", "color", "themeColor"].contains(key)
                }) else {
                @failure.reject("invalid-operation", "Unknown border property")
              }
              let themeColor = match properties.get("themeColor") {
                None | Some(Null) => None
                Some(String(slot)) => Some(slot)
                _ =>
                  @failure.reject(
                    "invalid-operation", "Invalid border theme slot",
                  )
              }
              Some({ style, width, color, themeColor, })
            }
            _ => @failure.reject("invalid-operation", "Invalid border patch")
          }
        }
        if action == "tableBorders" {
          @model.TableBorders(patch)
        } else {
          @model.CellBorders(patch)
        }
      }
      "rowBefore" => @model.RowBefore
      "rowAfter" => @model.RowAfter
      "deleteRow" => @model.DeleteRow
      "columnBefore" => @model.ColumnBefore
      "columnAfter" => @model.ColumnAfter
      "deleteColumn" => @model.DeleteColumn
      "merge" =>
        @model.MergeCells(
          field_int(fields, "rows"),
          field_int(fields, "columns"),
        )
      "unmerge" => @model.UnmergeCell
      "splitCell" =>
        @model.SplitCell(
          field_int(fields, "rows"),
          field_int(fields, "columns"),
        )
      "splitTable" => @model.SplitTable
      "pasteCells" => @model.PasteCells(field_string(fields, "text"))
      "pasteFragment" =>
        @model.PasteCellFragment(field_string(fields, "fragment"))
      "headerRows" => @model.HeaderRows(field_int(fields, "value"))
      "rowSplit" =>
        @model.RowSplit(
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
        let theme = match fields {
          { "themeColor": Null, .. } => None
          { "themeColor": String(value), .. } => Some(value)
          Object(values) if !values.contains("themeColor") => None
          _ =>
            @failure.reject(
              "invalid-operation", "Cell fill theme requires a slot or null",
            )
        }
        @model.CellFill(color, theme)
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
        @model.CellVerticalAlign(value)
      }
      "tableAlign" => @model.TableAlign(field_string(fields, "value"))
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
          @model.TableMargins(value)
        } else {
          @model.CellMargins(value)
        }
      }
      "tableWidth" | "rowHeight" | "columnWidth" as action => {
        guard fields is { "value": Number(value, ..), .. } else {
          @failure.reject("invalid-operation", "Table size number is required")
        }
        if action == "columnWidth" {
          @model.ColumnWidth(field_int(fields, "column"), value)
        } else if action == "tableWidth" {
          @model.TableWidth(value)
        } else {
          @model.RowHeight(value, field_string(fields, "rule"))
        }
      }
      _ => @failure.reject("invalid-operation", "Unknown table edit")
    }
    session.edit_table(
      revision,
      selection,
      change,
      probe=self.probe,
      profile=font_profile(request),
      images=self.images,
    )
  }
  self.layout = None
  result
}
