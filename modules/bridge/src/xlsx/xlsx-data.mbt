///|
#derive(@json.FromJson)
priv struct SubtotalRequest {
  range : String
  groupColumn : @common.RequestInt
  valueColumn : @common.RequestInt
  operation : String
}

///|
#derive(@json.FromJson)
priv struct DataEditRequest[T] {
  settings : T
  sourceRevision : @common.RequestInt
  overwrite : Bool?
}

///|
#derive(@json.FromJson)
priv struct TextColumnRequest {
  range : String
  delimiter : String?
  breaks : Array[@common.RequestInt]?
  types : Array[String]?
  formulas : Bool?
}

///|
#derive(@json.FromJson)
priv struct DuplicateRequest {
  range : String
  header : Bool
  columns : Array[@common.RequestInt]
}

///|
priv struct SubtotalSettingsInput {
  value : @model.SubtotalSettings
}

///|
impl @json.FromJson for SubtotalSettingsInput with fn from_json(value, path) {
  guard value is Object(fields) && fields.length() == 4 else {
    raise @json.JsonDecodeError((path, "Invalid subtotal settings"))
  }
  let settings : SubtotalRequest = @json.from_json(value, path~)
  {
    value: {
      range: settings.range,
      groupColumn: settings.groupColumn.value,
      valueColumn: settings.valueColumn.value,
      operation: settings.operation,
    },
  }
}

///|
priv struct ConsolidateSettingsInput {
  value : @model.ConsolidateSettings
}

///|
impl @json.FromJson for ConsolidateSettingsInput with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("sources") is Some(Array(sources)) &&
    !sources.is_empty() &&
    sources.length() <= @model.ConsolidationSources else {
    raise @json.JsonDecodeError((path, "Invalid consolidation settings"))
  }
  guard sources.all(source => source is Object(fields) && fields.length() == 2) else {
    raise @json.JsonDecodeError(
      (path.add_key("sources"), "Invalid consolidation source"),
    )
  }
  { value: @json.from_json(value, path~), }
}

///|
fn xlsx_data_edit(
  action : String,
  change : Json,
) -> @model.SheetEdit raise @failure.Failure {
  let overwrite = action == "textToColumns" || action == "consolidate"
  let keys = if !overwrite {
    ["action", "settings", "sourceRevision"]
  } else {
    ["action", "settings", "sourceRevision", "overwrite"]
  }
  guard change is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) &&
    (!overwrite || fields.get("overwrite") is Some(True | False)) else {
    @failure.reject("invalid-operation", "Invalid data operation command")
  }
  match action {
    "createSubtotals" => {
      let command : DataEditRequest[SubtotalSettingsInput] = @common.request(
        change,
      )
      @model.CreateSubtotals(
        command.settings.value,
        command.sourceRevision.value,
      )
    }
    "removeDuplicates" => {
      let command : DataEditRequest[DuplicateSettingsInput] = @common.request(
        change,
      )
      @model.RemoveDuplicates(
        command.settings.value,
        command.sourceRevision.value,
      )
    }
    "textToColumns" => {
      let command : DataEditRequest[TextColumnSettingsInput] = @common.request(
        change,
      )
      @model.TextToColumns(
        command.settings.value,
        command.sourceRevision.value,
        command.overwrite.unwrap_or(false),
      )
    }
    "consolidate" => {
      let command : DataEditRequest[ConsolidateSettingsInput] = @common.request(
        change,
      )
      @model.Consolidate(
        command.settings.value,
        command.sourceRevision.value,
        command.overwrite.unwrap_or(false),
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown data operation")
  }
}

///|
priv struct TextColumnSettingsInput {
  value : @model.TextColumnSettings
}

///|
impl @json.FromJson for TextColumnSettingsInput with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields.length() <= 4 &&
    fields
    .iter()
    .all(pair => {
      match pair {
        (_, Null) => false
        ("range" | "delimiter" | "breaks" | "types" | "formulas", _) => true
        _ => false
      }
    }) &&
    fields.contains("delimiter") != fields.contains("breaks") else {
    raise @json.JsonDecodeError((path, "Invalid text to columns settings"))
  }
  if fields.get("breaks") is Some(value) {
    guard value is Array(breaks) &&
      !breaks.is_empty() &&
      breaks.length() < @model.TextColumnCells else {
      raise @json.JsonDecodeError(
        (path.add_key("breaks"), "Invalid text to columns split"),
      )
    }
  }
  if fields.get("types") is Some(value) {
    guard value is Array(types) && types.length() <= @model.TextColumnCells else {
      raise @json.JsonDecodeError(
        (path.add_key("types"), "Invalid column types"),
      )
    }
  }
  let settings : TextColumnRequest = @json.from_json(value, path~)
  let split = match (settings.delimiter, settings.breaks) {
    (Some(delimiter), None) => @model.Delimited(delimiter)
    (None, Some(breaks)) =>
      @model.Fixed(
        breaks.map(value => {
          guard value.value >= 1 &&
            value.value <= @model.TextColumnBreakPosition else {
            raise @json.JsonDecodeError(
              (path.add_key("breaks"), "Invalid fixed-width position"),
            )
          }
          value.value
        }),
      )
    _ => raise @json.JsonDecodeError((path, "Invalid text to columns split"))
  }
  {
    value: {
      range: settings.range,
      split,
      types: settings.types.unwrap_or([]),
      formulas: settings.formulas.unwrap_or(false),
    },
  }
}

///|
priv struct DuplicateSettingsInput {
  value : @model.DuplicateSettings
}

///|
impl @json.FromJson for DuplicateSettingsInput with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.get("columns") is Some(Array(columns)) &&
    !columns.is_empty() &&
    columns.length() <= @model.DuplicateCells else {
    raise @json.JsonDecodeError((path, "Invalid duplicate settings"))
  }
  let settings : DuplicateRequest = @json.from_json(value, path~)
  {
    value: {
      range: settings.range,
      header: settings.header,
      columns: settings.columns.map(value => {
        guard value.value >= 1 && value.value <= @model.WorksheetColumns else {
          raise @json.JsonDecodeError(
            (path.add_key("columns"), "Invalid duplicate comparison column"),
          )
        }
        value.value
      }),
    },
  }
}
