///|
priv struct ChartReferences {
  value : Array[String]
}

///|
impl @json.FromJson for ChartReferences with fn from_json(input, path) {
  guard input is Array(items) && items.length() <= @model.ChartSeriesCount else {
    raise @json.JsonDecodeError((path, "Chart reference list exceeds limits"))
  }
  { value: @json.from_json(input, path~), }
}

///|
#derive(@json.FromJson)
priv struct ChartSettingsRequest {
  kind : String
  title : String
  label : String
  legend : String
  holeSize : @common.RequiredNullable[@common.RequestInt]
  categories : String
  names : ChartReferences
  values : ChartReferences
}

///|
priv struct ChartSettingsInput {
  value : @model.SheetChartSettings
}

///|
impl @json.FromJson for ChartSettingsInput with fn from_json(input, path) {
  guard input is Object(fields) &&
    fields.length() == 8 &&
    fields
    .keys()
    .all(key => {
      [
        "kind", "title", "label", "legend", "holeSize", "categories", "names", "values",
      ].contains(key)
    }) else {
    raise @json.JsonDecodeError((path, "Chart settings require known fields"))
  }
  let command : ChartSettingsRequest = @json.from_json(input, path~)
  {
    value: {
      kind: command.kind,
      title: command.title,
      label: command.label,
      legend: command.legend,
      hole_size: command.holeSize.value.map(value => value.value),
      categories: command.categories,
      names: command.names.value,
      values: command.values.value,
    },
  }
}

///|
#derive(@json.FromJson)
priv struct InsertChartRequest {
  revision : @common.RequestInt
  sheet : String
  settings : ChartSettingsInput
  width : @common.RequestNumber
  height : @common.RequestNumber
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SetChartRequest {
  revision : @common.RequestInt
  sheet : String
  id : String
  settings : ChartSettingsInput
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct InsertRangeChartRequest {
  revision : @common.RequestInt
  sheet : String
  range : String
  kind : String
  title : String
  width : @common.RequestNumber
  height : @common.RequestNumber
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ObjectFrameCommand {
  revision : @common.RequestInt
  sheet : String
  id : String
  settings : ObjectFrameRequest
  profile : @common.RequestProfile
}

///|
let chart_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "getXlsxChart": (context, session, input) => {
    let command : SheetProfileRequest = @common.request(input)
    session.charts(
      command.revision.value,
      command.sheet,
      context.probe,
      command.profile.value,
    )
  },
  "insertXlsxChart": (context, session, input) => {
    let command : InsertChartRequest = @common.request(input)
    session.insert_chart(
      command.revision.value,
      command.sheet,
      command.settings.value,
      command.width.value,
      command.height.value,
      context.probe,
      command.profile.value,
    )
  },
  "setXlsxChart": (context, session, input) => {
    let command : SetChartRequest = @common.request(input)
    session.set_chart(
      command.revision.value,
      command.sheet,
      command.id,
      command.settings.value,
      context.probe,
      command.profile.value,
    )
  },
  "insertRangeXlsxChart": (context, session, input) => {
    let command : InsertRangeChartRequest = @common.request(input)
    session.insert_chart_range(
      command.revision.value,
      command.sheet,
      command.range,
      command.kind,
      command.title,
      command.width.value,
      command.height.value,
      context.probe,
      command.profile.value,
    )
  },
  "frameXlsxChart": (context, session, input) => {
    let command : ObjectFrameCommand = @common.request(input)
    let frame = command.settings
    session.set_chart_frame(
      command.revision.value,
      command.sheet,
      command.id,
      frame.anchor,
      frame.rect(),
      frame.name,
      frame.description,
      context.probe,
      command.profile.value,
    )
  },
  "deleteXlsxChart": (context, session, input) => {
    let command : ObjectIdRequest = @common.request(input)
    session.delete_chart(
      command.revision.value,
      command.sheet,
      command.id,
      context.probe,
      command.profile.value,
    )
  },
}
