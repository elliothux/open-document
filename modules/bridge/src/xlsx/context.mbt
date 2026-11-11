///|
#derive(ToJson)
priv struct XlsxInputLimits {
  fontBytes : Int32
  exportBytes : Int32
  drawingFragmentUnits : Int32
  imageBytes : Int32
  rgbaBytes : Int32
  delimitedBytes : Int32
}

///|
let session_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  let handlers = drawing_handlers.copy()
  for
    domain in [
      chart_handlers, shape_handlers, cell_handlers, data_handlers, thread_handlers,
      sheet_handlers, print_handlers,
    ] {
    for name, handler in domain {
      handlers[name] = handler
    }
  }
  handlers
}

///|
pub struct Context {
  probe : @layout.TextProbe
  output : @common.OutputBytes
  outlines : @common.OutlineDelta
  mut chart_tiles : Map[String, Json]
  mut xlsx : @model.Session?
  mut closed : Bool
  images : @layout.Images
  mut layout_id : Int32
  mut xlsx_print : (@layout.PositionedDocument, Int32, Int32)?
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    output: @common.OutputBytes::new(),
    outlines: @common.OutlineDelta::new(),
    chart_tiles: Map([]),
    xlsx: None,
    closed: false,
    images: @layout.Images::new(),
    layout_id: 0,
    xlsx_print: None,
  }
}

///|
pub fn call(
  context : Context,
  input : String,
  first~ : String = "",
  second~ : String = "",
) -> String {
  context.output.clear()
  response(() => {
    errdefer context.output.clear()
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let request = parse_request(input, first~, second~)
    let command : @common.OperationRequest = @common.request(request)
    let operation = command.operation
    if lifecycle_handlers.get(operation) is Some(handler) {
      return context.outlines.drawing(handler(context, request))
    }
    if analysis_handlers.get(operation) is Some(handler) {
      return context.outlines.drawing(handler(context, request))
    }
    guard context.xlsx is Some(session) else {
      @failure.reject("session-required", "Open an XLSX workbook first")
    }
    if session_handlers.get(operation) is Some(handler) {
      return context.outlines.drawing(handler(context, session, request))
    }
    @failure.reject("invalid-operation", "Unknown XLSX operation")
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font_wire(input, identity, font_input_bytes)
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
  context.output.clear()
  context.outlines.clear()
  context.chart_tiles.clear()
  context.probe.close()
  if context.xlsx is Some(session) {
    session.close()
  }
  context.xlsx = None
  context.xlsx_print = None
  context.images.clear()
}

///|
pub fn take_output(context : Context, slot : Int32) -> String? {
  context.output.take_string(slot)
}
