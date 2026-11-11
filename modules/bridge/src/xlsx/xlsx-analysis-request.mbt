///|
#derive(@json.FromJson)
priv struct AnalysisInsertSettings {
  pivot : String
  field : @common.RequestInt
  name : String
  caption : String
  width : @common.RequestNumber
  height : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct AnalysisInsertRequest {
  revision : @common.RequestInt
  sheet : String
  settings : AnalysisInsertSettings
  profile : @common.RequestProfile
}

///|
fn Context::analysis_insert_request(
  self : Context,
  request : Json,
  kind : String,
) -> (@model.Session, AnalysisInsertRequest) raise @failure.Failure {
  guard self.xlsx is Some(session) &&
    request is { "settings": Object(fields), .. } &&
    fields.length() == 6 &&
    fields
    .keys()
    .all(key => {
      ["pivot", "field", "name", "caption", "width", "height"].contains(key)
    }) else {
    @failure.reject(
      "invalid-operation",
      "Native " + kind + " settings are required",
    )
  }
  (session, @common.request(request))
}

///|
fn Context::insert_xlsx_slicer(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  let (session, command) = self.analysis_insert_request(request, "slicer")
  let settings = command.settings
  session.insert_slicer(
    command.revision.value,
    command.sheet,
    {
      pivot: settings.pivot,
      field: settings.field.value,
      name: settings.name,
      caption: settings.caption,
      width: settings.width.value,
      height: settings.height.value,
    },
    self.probe,
    command.profile.value,
  )
}

///|
fn Context::insert_xlsx_timeline(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  let (session, command) = self.analysis_insert_request(request, "timeline")
  let settings = command.settings
  session.insert_timeline(
    command.revision.value,
    command.sheet,
    {
      pivot: settings.pivot,
      field: settings.field.value,
      name: settings.name,
      caption: settings.caption,
      width: settings.width.value,
      height: settings.height.value,
    },
    self.probe,
    command.profile.value,
  )
}

///|
#derive(@json.FromJson)
priv struct AnalysisFrameSettings {
  anchor : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
}

///|
fn AnalysisFrameSettings::rect(self : AnalysisFrameSettings) -> @layout.Border {
  {
    x: self.x.value,
    y: self.y.value,
    width: self.width.value,
    height: self.height.value,
  }
}

///|
#derive(@json.FromJson)
priv struct AnalysisFrameRequest {
  revision : @common.RequestInt
  sheet : String
  objectId : String
  frame : AnalysisFrameSettings
  profile : @common.RequestProfile
}

///|
fn Context::set_xlsx_analysis_frame(
  self : Context,
  request : Json,
  timeline~ : Bool = false,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) &&
    request is { "frame": Object(fields), .. } &&
    fields.length() == 5 &&
    fields
    .keys()
    .all(key => ["anchor", "x", "y", "width", "height"].contains(key)) else {
    @failure.reject("invalid-operation", "Native analysis frame is required")
  }
  let command : AnalysisFrameRequest = @common.request(request)
  let frame = command.frame
  let set_frame = if timeline {
    @model.Session::set_timeline_frame
  } else {
    @model.Session::set_slicer_frame
  }
  set_frame(
    session,
    command.revision.value,
    command.sheet,
    command.objectId,
    frame.anchor,
    frame.rect(),
    self.probe,
    command.profile.value,
  )
}

///|
let analysis_handlers : Map[
  String,
  (Context, Json) -> Json raise @failure.Failure,
] = {
  "insertXlsxTimeline": (context, input) => context.insert_xlsx_timeline(input),
  "insertXlsxSlicer": (context, input) => context.insert_xlsx_slicer(input),
  "frameXlsxTimeline": (context, input) => {
    context.set_xlsx_analysis_frame(input, timeline=true)
  },
  "frameXlsxSlicer": (context, input) => context.set_xlsx_analysis_frame(input),
}
