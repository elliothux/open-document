///|
priv struct SheetEditRequest {
  revision : @common.RequestInt
  sheet : String
  change : Json
  date : String?
} derive(@json.FromJson)

///|
priv struct ConditionalRuleEditRequest {
  ranges : String
  priority : @common.RequiredNullable[@common.RequestInt]
  rule : @common.RequiredNullable[ConditionalSettingsRequest]
  sourceRevision : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct ValidationEditRequest {
  range : String
  rule : Json
} derive(@json.FromJson)

///|
priv struct AxisEditRequest {
  first : @common.RequestInt
  count : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct AxisSizeRequest {
  first : @common.RequestInt
  last : @common.RequestInt
  size : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct FreezeRequest {
  rows : @common.RequestInt
  columns : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct RangeDirectionRequest {
  range : String
  direction : String
} derive(@json.FromJson)

///|
priv struct MoveCellsRequest {
  sourceSheet : String
  source : String
  destination : String
} derive(@json.FromJson)

///|
priv struct SheetViewRequest {
  gridLines : Bool
  headings : Bool
  rtl : Bool
  formulas : Bool
} derive(@json.FromJson)

///|
priv struct DefineNameRequest {
  original : @common.RequiredNullable[String]
  name : String
  scope : @common.RequiredNullable[String]
  formula : String
} derive(@json.FromJson)

///|
priv struct NameTargetRequest {
  name : String
  scope : @common.RequiredNullable[String]
} derive(@json.FromJson)

///|
priv struct HyperlinkEditRequest {
  range : String
  target : @common.RequiredNullable[String]
} derive(@json.FromJson)

///|
priv struct OpenHyperlinkRequest {
  range : String
  sourceRevision : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct SheetActionRequest {
  action : String
} derive(@json.FromJson)

///|
priv struct SheetProtectionRequest {
  enabled : Bool
  password : String?
} derive(@json.FromJson)

///|
priv struct ConditionalPriorityRequest {
  priority : @common.RequestInt
  position : @common.RequestInt
  sourceRevision : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct CellNoteRequest {
  cell : String
  text : @common.RequiredNullable[String]
  author : String?
} derive(@json.FromJson)

///|
priv struct ValidationValueRequest {
  index : @common.RequestInt
  sourceRevision : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct MergeCellsRequest {
  range : String
  discard : Bool
} derive(@json.FromJson)

///|
priv struct SheetRangeRequest {
  range : String
} derive(@json.FromJson)

///|
priv struct SheetMoveRequest {
  index : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct SheetVisibilityRequest {
  state : String
} derive(@json.FromJson)

///|
priv struct SheetRenameRequest {
  name : String
} derive(@json.FromJson)

///|
priv struct SeriesRequest {
  mode : String
  source : String
  range : String
  direction : String
} derive(@json.FromJson)

///|
priv struct DateSeriesRequest {
  unit : String
  step : @common.RequestNumber
} derive(@json.FromJson)

///|
fn xlsx_sheet_edit(
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let command : SheetEditRequest = @common.request(request)
  let change = command.change
  let kind : SheetActionRequest = @common.request(change)
  let action = kind.action
  let change = match action {
    "createPivot"
    | "refreshPivot"
    | "updatePivot"
    | "deletePivot"
    | "filterSlicer"
    | "selectSlicer"
    | "scrollSlicer"
    | "deleteSlicer"
    | "filterTimeline"
    | "deleteTimeline"
    | "setTimelineLevel"
    | "scrollTimeline"
    | "setTimelineEndpoint" =>
      return xlsx_pivot_edit(
        session,
        command.revision.value,
        command.sheet,
        action,
        change,
      )
    "protection" | "workbookProtection" => {
      guard change is Object(fields) &&
        fields.keys().all(k => ["action", "enabled", "password"].contains(k)) &&
        !(change is { "password": Null, .. }) else {
        @failure.reject(
          "invalid-operation", "Invalid worksheet protection fields",
        )
      }
      let salt = match request {
        { "passwordSalt": String(value), .. } =>
          @common.byte_input(value, 18) catch {
            _ =>
              @failure.reject(
                "invalid-operation", "Invalid worksheet password salt",
              )
          }
        _ => b""
      }
      let settings : SheetProtectionRequest = @common.request(change)
      let password = settings.password.unwrap_or("")
      if action == "workbookProtection" {
        @model.WorkbookProtection(settings.enabled, password, salt)
      } else {
        @model.Protection(settings.enabled, password, salt)
      }
    }
    "add" => @model.Add
    "copy" => @model.Copy
    "textToColumns" | "removeDuplicates" | "consolidate" | "createSubtotals" =>
      xlsx_data_edit(action, change)
    "delete" => @model.Delete
    "sparkline" => xlsx_sparkline_edit(change)
    "conditionalRule" => {
      let request : ConditionalRuleEditRequest = @common.request(change)
      @model.ConditionalRule(
        request.ranges,
        request.priority.value.map(value => value.value),
        request.rule.value.map(rule => rule.value),
        request.sourceRevision.value,
      )
    }
    "conditionalPriority" => {
      let request : ConditionalPriorityRequest = @common.request(change)
      @model.ConditionalPriority(
        request.priority.value,
        request.position.value,
        request.sourceRevision.value,
      )
    }
    "drawingOrder" => xlsx_drawing_order(change)
    "duplicateDrawing" => xlsx_duplicate_drawing(change)
    "moveDrawing" => xlsx_move_drawing(change)
    "note" => {
      guard change is Object(fields) &&
        fields.keys().all(k => ["action", "cell", "text", "author"].contains(k)) &&
        !(change is { "author": Null, .. }) else {
        @failure.reject("invalid-operation", "Invalid cell note command fields")
      }
      let request : CellNoteRequest = @common.request(change)
      @model.Note(
        request.cell,
        request.text.value,
        request.author.unwrap_or(""),
      )
    }
    "hyperlink" => {
      guard change is Object(fields) &&
        fields.length() == 3 &&
        fields.keys().all(k => ["action", "range", "target"].contains(k)) else {
        @failure.reject("invalid-operation", "Invalid hyperlink command fields")
      }
      let request : HyperlinkEditRequest = @common.request(change)
      @model.Hyperlink(request.range, request.target.value)
    }
    "openHyperlink" => {
      guard change is Object(fields) &&
        fields.length() == 3 &&
        fields
        .keys()
        .all(k => ["action", "range", "sourceRevision"].contains(k)) else {
        @failure.reject(
          "invalid-operation", "Invalid hyperlink navigation fields",
        )
      }
      let request : OpenHyperlinkRequest = @common.request(change)
      @model.OpenHyperlink(request.range, request.sourceRevision.value)
    }
    "validation" => {
      let request : ValidationEditRequest = @common.request(change)
      @model.Validation(
        request.range,
        if request.rule is Null {
          None
        } else {
          Some(@common.request(request.rule))
        },
      )
    }
    "validationValue" => {
      let request : ValidationValueRequest = @common.request(change)
      @model.ValidationValue(request.index.value, request.sourceRevision.value)
    }
    "merge" => {
      let request : MergeCellsRequest = @common.request(change)
      @model.Merge(request.range, request.discard)
    }
    "unmerge" => {
      let request : SheetRangeRequest = @common.request(change)
      @model.Unmerge(request.range)
    }
    "sort" => xlsx_sort(change)
    "filter" => xlsx_filter(change)
    "group"
    | "ungroup"
    | "collapseGroup"
    | "clearOutline"
    | "outlineSummary"
    | "renameTable"
    | "createTable"
    | "resizeTable"
    | "tableColumnFormula"
    | "tableTotals"
    | "tableStyle"
    | "tableStyleDefinition"
    | "deleteTableStyle"
    | "tableTotal"
    | "tableFilter"
    | "tableFilterClear"
    | "tableFilterRemove"
    | "tableFilterReapply"
    | "renameTableColumn" => xlsx_table_edit(action, change)
    "filterClear" => @model.ClearFilter
    "filterRemove" => @model.RemoveFilter
    "filterReapply" => @model.ReapplyFilter
    "series" => {
      let request : SeriesRequest = @common.request(change)
      @model.Series(
        match request.mode {
          "linear" => @model.Linear
          "growth" => @model.Growth
          "text" => @model.TextSeries
          "auto" => @model.Automatic
          "copy" => @model.CopySeries
          "shrink" => @model.Shrink
          "date" => {
            let date : DateSeriesRequest = @common.request(change)
            @model.Date(date.unit, date.step.value)
          }
          _ => @failure.reject("invalid-operation", "Invalid series mode")
        },
        request.source,
        request.range,
        request.direction,
      )
    }
    "view" => {
      let request : SheetViewRequest = @common.request(change)
      @model.View({
        grid_lines: request.gridLines,
        headings: request.headings,
        rtl: request.rtl,
        formulas: request.formulas,
      })
    }
    "name" => {
      let request : DefineNameRequest = @common.request(change)
      @model.SetName({
        original: request.original.value,
        name: request.name,
        scope: request.scope.value,
        formula: request.formula,
      })
    }
    "nameDelete" | "nameSelect" => {
      let request : NameTargetRequest = @common.request(change)
      if action == "nameDelete" {
        @model.DeleteName(request.name, request.scope.value)
      } else {
        @model.SelectName(request.name, request.scope.value)
      }
    }
    "freeze" => {
      let request : FreezeRequest = @common.request(change)
      @model.Freeze(request.rows.value, request.columns.value)
    }
    "pageSetup" => @model.PageSetup(xlsx_sheet_page_setup(change))
    "printRange" => @model.PrintRange(xlsx_sheet_print_range(change))
    "headerFooter" => @model.HeaderFooter(xlsx_sheet_header_footer(change))
    "move" => {
      let request : SheetMoveRequest = @common.request(change)
      @model.Move(request.index.value)
    }
    "insertRows" | "deleteRows" | "insertColumns" | "deleteColumns" => {
      let request : AxisEditRequest = @common.request(change)
      let first = request.first.value
      let count = request.count.value
      match action {
        "insertRows" => @model.InsertRows(first, count)
        "deleteRows" => @model.DeleteRows(first, count)
        "insertColumns" => @model.InsertColumns(first, count)
        _ => @model.DeleteColumns(first, count)
      }
    }
    "insertCells" | "deleteCells" | "fill" => {
      let request : RangeDirectionRequest = @common.request(change)
      match action {
        "insertCells" => @model.InsertCells(request.range, request.direction)
        "deleteCells" => @model.DeleteCells(request.range, request.direction)
        _ => @model.Fill(request.range, request.direction)
      }
    }
    "moveCells" => {
      let request : MoveCellsRequest = @common.request(change)
      @model.MoveCells(request.sourceSheet, request.source, request.destination)
    }
    "visibility" => {
      let request : SheetVisibilityRequest = @common.request(change)
      @model.Visibility(request.state)
    }
    "rename" => {
      let request : SheetRenameRequest = @common.request(change)
      @model.Rename(request.name)
    }
    "rowHeight" | "columnWidth" => {
      let request : AxisSizeRequest = @common.request(change)
      let first = request.first.value
      let last = request.last.value
      let size = request.size.value
      if action == "rowHeight" {
        @model.RowHeight(first, last, size)
      } else {
        @model.ColumnWidth(first, last, size)
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown worksheet edit")
  }
  session.edit_sheet(
    command.revision.value,
    command.sheet,
    change,
    date=command.date,
  )
}

///|
let sheet_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "editXlsxSheet": (_context, session, input) => xlsx_sheet_edit(session, input),
}
