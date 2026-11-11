///|
priv struct TableStructureRequest {
  operation : String
} derive(@json.FromJson)

///|
priv struct TableDimensionRequest {
  value : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct TableDirectionRequest {
  rtl : Bool
} derive(@json.FromJson)

///|
priv struct TableSizeRequest {
  rows : @common.RequestInt
  columns : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct InsertTableRequest {
  rows : @common.RequestInt
  columns : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
fn pptx_table_edit(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  match action {
    "tableStructure" => {
      let request : TableStructureRequest = @common.request(change)
      @model.TableStructure(request.operation)
    }
    "tableRowHeight" | "tableColumnWidth" => {
      let request : TableDimensionRequest = @common.request(change)
      if action == "tableRowHeight" {
        @model.TableRowHeight(request.value.value)
      } else {
        @model.TableColumnWidth(request.value.value)
      }
    }
    "tableStyle" => {
      guard change is { "style": Object(fields) as style, .. } &&
        fields.length() == 7 else {
        @failure.reject("invalid-operation", "Invalid table style settings")
      }
      @model.TableStyle(@common.request(style))
    }
    "tableDirection" => {
      let request : TableDirectionRequest = @common.request(change)
      @model.TableDirection(request.rtl)
    }
    "splitTableCell" | "fillTable" => {
      let request : TableSizeRequest = @common.request(change)
      if action == "splitTableCell" {
        @model.SplitTableCell(request.rows.value, request.columns.value)
      } else {
        @model.FillTable(request.rows.value, request.columns.value)
      }
    }
    "insertTable" => {
      let request : InsertTableRequest = @common.request(change)
      @model.InsertTable(
        request.rows.value,
        request.columns.value,
        request.x.value,
        request.y.value,
        request.width.value,
        request.height.value,
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown table edit")
  }
}
