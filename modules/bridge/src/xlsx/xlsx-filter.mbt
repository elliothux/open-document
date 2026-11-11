///|
priv struct FilterColumnRequest {
  kind : String
  column : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct IconFilterRequest {
  iconSet : String
  iconId : @common.RequiredNullable[@common.RequestInt]
} derive(@json.FromJson)

///|
priv struct RelativeDateFilterRequest {
  period : String
} derive(@json.FromJson)

///|
priv struct CalendarFilterRequest {
  unit : String
  value : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct ColorFilterRequest {
  color : @common.RequiredNullable[String]
  cellColor : Bool
} derive(@json.FromJson)

///|
priv struct DateGroupFilterRequest {
  groups : Array[String]
  values : Array[String]
  blank : Bool
} derive(@json.FromJson)

///|
priv struct AverageFilterRequest {
  above : Bool
} derive(@json.FromJson)

///|
priv struct RankFilterRequest {
  value : @common.RequestInt
  top : Bool
  percent : Bool
} derive(@json.FromJson)

///|
priv struct ValueFilterRequest {
  values : Array[String]
  blank : Bool
} derive(@json.FromJson)

///|
priv struct CustomFilterRequest {
  conditions : Array[@model.FilterCondition]
  all : Bool
} derive(@json.FromJson)

///|
fn xlsx_filter(change : Json) -> @model.SheetEdit raise @failure.Failure {
  let input : SheetRangeRequest = @common.request(change)
  @model.SetFilter({ range: input.range, columns: xlsx_filter_columns(change), })
}

///|
fn xlsx_filter_columns(
  change : Json,
) -> Array[@model.FilterColumn] raise @failure.Failure {
  guard change is { "columns": Array(columns), .. } &&
    columns.length() <= @model.FilterColumns else {
    @failure.reject("invalid-operation", "Bounded filter columns are required")
  }
  columns.map(xlsx_filter_column)
}

///|
fn xlsx_filter_column(
  column : Json,
) -> @model.FilterColumn raise @failure.Failure {
  guard column is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid filter column")
  }
  let input : FilterColumnRequest = @common.request(column)
  let rule = match input.kind {
    "icon" if fields.length() == 4 => {
      let request : IconFilterRequest = @common.request(column)
      @model.Icon(request.iconSet, request.iconId.value.map(id => id.value))
    }
    "relativeDate" if fields.length() == 3 => {
      let request : RelativeDateFilterRequest = @common.request(column)
      @model.Relative(request.period, None)
    }
    "calendar" if fields.length() == 4 => {
      let request : CalendarFilterRequest = @common.request(column)
      @model.Calendar(request.unit, request.value.value)
    }
    "color" if fields.length() == 4 => {
      let request : ColorFilterRequest = @common.request(column)
      @model.Color(request.color.value, cell_color=request.cellColor)
    }
    "dates" if fields.length() == 5 &&
      column is { "groups": Array(groups), "values": Array(values), .. } &&
      !groups.is_empty() &&
      groups.length() + values.length() <= @model.FilterEntries => {
      let request : DateGroupFilterRequest = @common.request(column)
      @model.Dates(request.groups, values=request.values, blank=request.blank)
    }
    "average" if fields.length() == 3 => {
      let request : AverageFilterRequest = @common.request(column)
      @model.Average(above=request.above)
    }
    "rank" if fields.length() == 5 => {
      let request : RankFilterRequest = @common.request(column)
      @model.Rank(request.value.value, top=request.top, percent=request.percent)
    }
    "values" if column is { "values": Array(values), .. } &&
      values.length() <= @model.FilterEntries => {
      let request : ValueFilterRequest = @common.request(column)
      @model.Values(request.values, blank=request.blank)
    }
    "custom" if column is { "conditions": Array(conditions), .. } &&
      conditions.length() >= 1 &&
      conditions.length() <= 2 => {
      let request : CustomFilterRequest = @common.request(column)
      @model.Custom(request.conditions, all=request.all)
    }
    _ => @failure.reject("invalid-operation", "Invalid filter rule")
  }
  { column: input.column.value, rule, }
}
