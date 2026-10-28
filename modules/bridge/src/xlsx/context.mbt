///|
pub struct Context {
  probe : @layout.TextProbe
  mut xlsx : @model.Session?
  mut closed : Bool
  images : @layout.Images
  mut layout_id : Int
  mut xlsx_print : (@layout.PositionedDocument, Int, Int)?
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    xlsx: None,
    closed: false,
    images: @layout.Images::new(),
    layout_id: 0,
    xlsx_print: None,
  }
}

///|
pub fn call(context : Context, input : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let request = parse_request(input)
    let operation = field_string(request, "operation")
    if operation == "budget" {
      return archive_budget()
    }
    if operation == "insertXlsxTimeline" {
      return context.insert_xlsx_timeline(request)
    }
    if operation == "insertXlsxSlicer" {
      return context.insert_xlsx_slicer(request)
    }
    if operation == "frameXlsxSlicer" || operation == "frameXlsxTimeline" {
      return context.set_xlsx_analysis_frame(
        request,
        timeline=operation == "frameXlsxTimeline",
      )
    }
    if operation.has_suffix("XlsxChart") {
      return context.xlsx_chart_operation(operation, request)
    }
    if operation == "shapesXlsx" ||
      operation == "insertShapeXlsx" ||
      operation == "setShapeXlsx" ||
      operation == "deleteShapeXlsx" {
      return context.xlsx_shape_operation(operation, request)
    }
    if xlsx_drawing_request(operation) {
      return context.xlsx_drawing_operation(operation, request)
    }
    context.xlsx_operation(operation, request)
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font(font_input_bytes(input), identity)
    context.xlsx_print = None
    if context.xlsx is Some(session) {
      session.invalidate_geometry()
    }
    { "font": index }
  })
}

///|
pub fn close(context : Context) -> Unit {
  if context.closed {
    return
  }
  context.closed = true
  context.probe.close()
  if context.xlsx is Some(session) {
    session.close()
  }
  context.xlsx = None
  context.xlsx_print = None
  context.images.clear()
}
