///|
#derive(@json.FromJson)
priv struct TableIdRequest {
  id : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct TableStyleDefinitionRequest {
  original : @common.RequiredNullable[String]
  name : String
  elements : Array[TableStyleRegionRequest]
}

///|
#derive(@json.FromJson)
priv struct TableStyleDeleteRequest {
  name : String
  replacement : @common.RequiredNullable[String]
}

///|
#derive(@json.FromJson)
priv struct TableStyleRegionRequest {
  kind : String
  size : @common.RequestInt
  format : CellFormatRequest
  vertical : @common.RequiredNullable[@model.CellBorder]
  horizontal : @common.RequiredNullable[@model.CellBorder]
}

///|
#derive(@json.FromJson)
priv struct TableStyleRequest {
  id : @common.RequestInt
  style : TableStyleOptionsRequest
}

///|
#derive(@json.FromJson)
priv struct TableStyleOptionsRequest {
  name : @common.RequiredNullable[String]
  firstColumn : Bool
  lastColumn : Bool
  rowStripes : Bool
  columnStripes : Bool
}

///|
#derive(@json.FromJson)
priv struct TableTotalsRequest {
  id : @common.RequestInt
  visible : Bool
}

///|
#derive(@json.FromJson)
priv struct TableColumnTotalRequest {
  id : @common.RequestInt
  column : @common.RequestInt
  total : TableColumnTotalInput
}

///|
#derive(@json.FromJson)
priv struct TableColumnFormulaRequest {
  id : @common.RequestInt
  column : @common.RequestInt
  formula : @common.RequiredNullable[String]
}

///|
#derive(@json.FromJson)
priv struct TableResizeRequest {
  id : @common.RequestInt
  range : String
}

///|
#derive(@json.FromJson)
priv struct TableCreateRequest {
  range : String
  name : String
}

///|
#derive(@json.FromJson)
priv struct TableRenameRequest {
  id : @common.RequestInt
  name : String
}

///|
#derive(@json.FromJson)
priv struct TableColumnRenameRequest {
  id : @common.RequestInt
  column : @common.RequestInt
  name : String
}

///|
#derive(@json.FromJson)
priv struct OutlineGroupRequest {
  axis : String
  first : @common.RequestInt
  last : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct OutlineCollapseRequest {
  axis : String
  first : @common.RequestInt
  last : @common.RequestInt
  level : @common.RequestInt
  collapsed : Bool
}

///|
#derive(@json.FromJson)
priv struct OutlineAxisRequest {
  axis : String
}

///|
#derive(@json.FromJson)
priv struct OutlineSummaryRequest {
  axis : String
  after : Bool
}

///|
fn[T : @json.FromJson] table_request(
  input : Json,
  fields : Int32,
) -> T raise @failure.Failure {
  // Every decoded field is required. Exact cardinality excludes unknown fields.
  guard input is Object(values) && values.length() == fields else {
    @failure.reject("invalid-operation", "Invalid table edit fields")
  }
  @common.request(input)
}

///|
fn TableStyleRegionRequest::element(
  request : TableStyleRegionRequest,
) -> @model.TableStyleElement {
  {
    kind: request.kind,
    size: request.size.value,
    format: request.format.value,
    vertical: request.vertical.value,
    horizontal: request.horizontal.value,
  }
}

///|
priv struct TableColumnTotalInput {
  value : @model.TableTotal
}

///|
impl @json.FromJson for TableColumnTotalInput with fn from_json(input, path) {
  guard input is Object(fields) else {
    raise @json.JsonDecodeError((path, "Expected column total settings"))
  }
  let value = match (input, fields.length()) {
    ({ "kind": String("none"), .. }, 1) => @model.TableTotal::Clear
    ({ "kind": String("label"), "text": String(text), .. }, 2) =>
      @model.TableTotal::Label(text)
    ({ "kind": String("formula"), "formula": String(formula), .. }, 2) =>
      @model.TableTotal::Formula(formula)
    ({ "kind": String("aggregate"), "function": String(function), .. }, 2) =>
      @model.TableTotal::Aggregate(function)
    _ => raise @json.JsonDecodeError((path, "Invalid column total fields"))
  }
  { value, }
}

///|
fn xlsx_table_edit(
  action : String,
  change : Json,
) -> @model.SheetEdit raise @failure.Failure {
  match action {
    "tableStyleDefinition" => {
      guard change is { "elements": Array(elements), .. } &&
        elements.length() <= @model.TableStyleRegions else {
        @failure.reject("invalid-operation", "Invalid table style regions")
      }
      for element in elements {
        guard element is Object(fields) && fields.length() == 5 else {
          @failure.reject(
            "invalid-operation", "Invalid table style region fields",
          )
        }
        for key in ["vertical", "horizontal"] {
          guard fields.get(key) is Some(Null) ||
            (fields.get(key) is Some(Object(border)) && border.length() == 2) else {
            @failure.reject(
              "invalid-operation", "Invalid table style border fields",
            )
          }
        }
      }
      let request : TableStyleDefinitionRequest = table_request(change, 4)
      @model.TableStyleDefinition(
        request.original.value,
        request.name,
        request.elements.map(TableStyleRegionRequest::element),
      )
    }
    "deleteTableStyle" => {
      let request : TableStyleDeleteRequest = table_request(change, 3)
      @model.DeleteTableStyle(request.name, request.replacement.value)
    }
    "tableStyle" => {
      guard change is { "style": Object(fields), .. } && fields.length() == 5 else {
        @failure.reject("invalid-operation", "Invalid table style options")
      }
      let request : TableStyleRequest = table_request(change, 3)
      let style = request.style
      @model.TableStyle(request.id.value, {
        name: style.name.value,
        first_column: style.firstColumn,
        last_column: style.lastColumn,
        row_stripes: style.rowStripes,
        column_stripes: style.columnStripes,
      })
    }
    "tableFilter"
    | "tableFilterClear"
    | "tableFilterRemove"
    | "tableFilterReapply" => {
      let request : TableIdRequest = table_request(
        change,
        if action == "tableFilter" {
          3
        } else {
          2
        },
      )
      let id = request.id.value
      match action {
        "tableFilter" => @model.TableFilter(id, xlsx_filter_columns(change))
        "tableFilterClear" => @model.TableFilterClear(id)
        "tableFilterRemove" => @model.TableFilterRemove(id)
        _ => @model.TableFilterReapply(id)
      }
    }
    "tableTotals" => {
      let request : TableTotalsRequest = table_request(change, 3)
      @model.TableTotals(request.id.value, request.visible)
    }
    "tableTotal" => {
      let request : TableColumnTotalRequest = table_request(change, 4)
      @model.TableColumnTotal(
        request.id.value,
        request.column.value,
        request.total.value,
      )
    }
    "tableColumnFormula" => {
      let request : TableColumnFormulaRequest = table_request(change, 4)
      @model.TableColumnFormula(
        request.id.value,
        request.column.value,
        request.formula.value,
      )
    }
    "resizeTable" => {
      let request : TableResizeRequest = table_request(change, 3)
      @model.ResizeTable(request.id.value, request.range)
    }
    "createTable" => {
      let request : TableCreateRequest = table_request(change, 3)
      @model.CreateTable(request.range, request.name)
    }
    "group" | "ungroup" => {
      let request : OutlineGroupRequest = @common.request(change)
      @model.GroupOutline(
        request.axis,
        request.first.value,
        request.last.value,
        action == "ungroup",
      )
    }
    "collapseGroup" => {
      let request : OutlineCollapseRequest = @common.request(change)
      @model.CollapseOutline(
        request.axis,
        request.first.value,
        request.last.value,
        request.level.value,
        request.collapsed,
      )
    }
    "clearOutline" => {
      let input : OutlineAxisRequest = @common.request(change)
      @model.ClearOutline(input.axis)
    }
    "outlineSummary" => {
      let request : OutlineSummaryRequest = @common.request(change)
      @model.OutlineSummary(request.axis, request.after)
    }
    "renameTable" => {
      let request : TableRenameRequest = table_request(change, 3)
      @model.RenameTable(request.id.value, request.name)
    }
    "renameTableColumn" => {
      let request : TableColumnRenameRequest = table_request(change, 4)
      @model.RenameTableColumn(
        request.id.value,
        request.column.value,
        request.name,
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown table or outline action")
  }
}
