///|
priv struct PptxInputLimits {
  fontBytes : Int32
  exportBytes : Int32
  textFragmentUnits : Int32
  objectFragmentUnits : Int32
  importBytes : Int32
  imageBytes : Int32
  mediaBytes : Int32
  rgbaBytes : Int32
  showInkBatchPoints : Int32
} derive(ToJson)

///|
let session_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  let handlers = edit_handlers.copy()
  for
    domain in [
      view_handlers, gesture_handlers, show_handlers, import_handlers, search_handlers,
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
  mut pptx : @model.Session?
  mut closed : Bool
  images : @layout.Images
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    output: @common.OutputBytes::new(),
    outlines: @common.OutlineDelta::new(),
    pptx: None,
    closed: false,
    images: @layout.Images::new(),
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
    guard context.pptx is Some(session) else {
      @failure.reject("session-required", "Open a PPTX presentation first")
    }
    if session_handlers.get(operation) is Some(handler) {
      return context.outlines.drawing(handler(context, session, request))
    }
    @failure.reject("invalid-operation", "Unknown PPTX operation")
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font_wire(input, identity, font_input_bytes)
    if context.pptx is Some(session) {
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
  context.probe.close()
  if context.pptx is Some(session) {
    session.close()
  }
  context.pptx = None
  context.images.clear()
}

///|
pub fn take_output(context : Context, slot : Int32) -> String? {
  context.output.take_string(slot)
}
