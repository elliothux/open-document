///|
priv struct InsertTableRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  rows : @common.RequestInt
  columns : @common.RequestInt
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct EditTableRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  change : Json
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct TableAutoFitRequest {
  mode : String
} derive(@json.FromJson)

///|
priv struct TableSizeRequest {
  rows : @common.RequestInt
  columns : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TableTextRequest {
  text : String
} derive(@json.FromJson)

///|
priv struct TableFragmentRequest {
  fragment : String
} derive(@json.FromJson)

///|
priv struct TableCountRequest {
  value : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TableSplitRequest {
  value : Bool
} derive(@json.FromJson)

///|
priv struct TableAlignmentRequest {
  value : String
} derive(@json.FromJson)

///|
priv struct TableValueRequest {
  value : Json
} derive(@json.FromJson)

///|
priv struct TableFillRequest {
  value : Json
  themeColor : Json?
} derive(@json.FromJson)

///|
priv struct TableBorderRequest {
  style : String
  width : @common.RequestNumber
  color : String
  themeColor : Json?
} derive(@json.FromJson)

///|
priv struct TableMarginsRequest {
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
  left : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct TableWidthRequest {
  value : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct ColumnWidthRequest {
  column : @common.RequestInt
  value : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct RowHeightRequest {
  rule : String
  value : @common.RequestNumber
} derive(@json.FromJson)

///|
fn table_nullable_string(value : Json) -> String? raise @failure.Failure {
  if value is Null {
    None
  } else {
    Some(@common.request(value))
  }
}

///|
fn docx_table_change(fields : Json) -> @model.TableEdit raise @failure.Failure {
  let command : @common.ActionRequest = @common.request(fields)
  let action = command.action
  match action {
    "autoFit" => {
      let request : TableAutoFitRequest = @common.request(fields)
      @model.AutoFit(request.mode)
    }
    "tableBorders" | "cellBorders" => {
      let request : TableValueRequest = @common.request(fields)
      guard request.value is Object(values) else {
        @failure.reject("invalid-operation", "Border patch is required")
      }
      let patch : Map[String, @model.TableBorderStyle?] = Map([])
      for side, value in values {
        patch[side] = if value is Null {
          None
        } else {
          guard value is Object(properties) &&
            properties
            .keys()
            .all(key => ["style", "width", "color", "themeColor"].contains(key)) else {
            @failure.reject("invalid-operation", "Unknown border property")
          }
          let border : TableBorderRequest = @common.request(value)
          Some({
            style: border.style,
            width: border.width.value,
            color: border.color,
            themeColor: table_nullable_string(
              border.themeColor.unwrap_or(Json::null()),
            ),
          })
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
    "merge" | "splitCell" => {
      let request : TableSizeRequest = @common.request(fields)
      if action == "merge" {
        @model.MergeCells(request.rows.value, request.columns.value)
      } else {
        @model.SplitCell(request.rows.value, request.columns.value)
      }
    }
    "unmerge" => @model.UnmergeCell
    "splitTable" => @model.SplitTable
    "pasteCells" => {
      let request : TableTextRequest = @common.request(fields)
      @model.PasteCells(request.text)
    }
    "pasteFragment" => {
      let request : TableFragmentRequest = @common.request(fields)
      @model.PasteCellFragment(request.fragment)
    }
    "headerRows" => {
      let request : TableCountRequest = @common.request(fields)
      @model.HeaderRows(request.value.value)
    }
    "rowSplit" => {
      let request : TableSplitRequest = @common.request(fields)
      @model.RowSplit(request.value)
    }
    "cellFill" => {
      let request : TableFillRequest = @common.request(fields)
      @model.CellFill(
        table_nullable_string(request.value),
        table_nullable_string(request.themeColor.unwrap_or(Json::null())),
      )
    }
    "cellVerticalAlign" => {
      let request : TableValueRequest = @common.request(fields)
      @model.CellVerticalAlign(table_nullable_string(request.value))
    }
    "tableAlign" => {
      let request : TableAlignmentRequest = @common.request(fields)
      @model.TableAlign(request.value)
    }
    "cellMargins" | "tableMargins" => {
      let request : TableValueRequest = @common.request(fields)
      let value : @layout.CellMargins? = if request.value is Null {
        None
      } else {
        let margins : TableMarginsRequest = @common.request(request.value)
        Some({
          top: margins.top.value,
          right: margins.right.value,
          bottom: margins.bottom.value,
          left: margins.left.value,
        })
      }
      if action == "tableMargins" {
        @model.TableMargins(value)
      } else {
        @model.CellMargins(value)
      }
    }
    "tableWidth" => {
      let request : TableWidthRequest = @common.request(fields)
      @model.TableWidth(request.value.value)
    }
    "columnWidth" => {
      let request : ColumnWidthRequest = @common.request(fields)
      @model.ColumnWidth(request.column.value, request.value.value)
    }
    "rowHeight" => {
      let request : RowHeightRequest = @common.request(fields)
      @model.RowHeight(request.value.value, request.rule)
    }
    _ => @failure.reject("invalid-operation", "Unknown table edit")
  }
}

///|
fn Context::docx_table(
  self : Context,
  session : @model.Session,
  insert : Bool,
  request : Json,
) -> Json raise @failure.Failure {
  let result = if insert {
    let command : InsertTableRequest = @common.request(request)
    session.insert_table(
      command.revision.value,
      command.selection.selection(),
      command.rows.value,
      command.columns.value,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
  } else {
    let command : EditTableRequest = @common.request(request)
    session.edit_table(
      command.revision.value,
      command.selection.selection(),
      docx_table_change(command.change),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
  }
  self.layout = None
  result
}
