///|
#derive(@json.FromJson)
priv struct SheetRevisionRequest {
  revision : @common.RequestInt
  sheet : String
}

///|
#derive(@json.FromJson)
priv struct DataRequest[T] {
  revision : @common.RequestInt
  sheet : String
  settings : T
}

///|
#derive(@json.FromJson)
priv struct PivotPreviewRequest {
  revision : @common.RequestInt
  settings : PivotSettingsRequest
  part : String?
}

///|
let data_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "pivotsXlsx": (_context, session, input) => {
    let command : SheetRevisionRequest = @common.request(input)
    session.pivots(command.revision.value, command.sheet)
  },
  "slicersXlsx": (_context, session, input) => {
    let command : SheetRevisionRequest = @common.request(input)
    session.slicers(command.revision.value, command.sheet)
  },
  "timelinesXlsx": (_context, session, input) => {
    let command : SheetRevisionRequest = @common.request(input)
    session.timelines(command.revision.value, command.sheet)
  },
  "pivotPreviewXlsx": (_context, session, input) => {
    let command : PivotPreviewRequest = @common.request(input)
    session.pivot_preview(
      command.revision.value,
      command.settings.value,
      part=command.part,
    )
  },
  "duplicatesXlsx": (_context, session, input) => {
    let command : DataRequest[DuplicateSettingsInput] = @common.request(input)
    session.duplicates(
      command.revision.value,
      command.sheet,
      command.settings.value,
    )
  },
  "textColumnsXlsx": (_context, session, input) => {
    let command : DataRequest[TextColumnSettingsInput] = @common.request(input)
    session.text_columns(
      command.revision.value,
      command.sheet,
      command.settings.value,
    )
  },
  "consolidationXlsx": (_context, session, input) => {
    let command : DataRequest[ConsolidateSettingsInput] = @common.request(input)
    session.consolidation(
      command.revision.value,
      command.sheet,
      command.settings.value,
    )
  },
  "subtotalsXlsx": (_context, session, input) => {
    let command : DataRequest[SubtotalSettingsInput] = @common.request(input)
    session.subtotals(
      command.revision.value,
      command.sheet,
      command.settings.value,
    )
  },
}
