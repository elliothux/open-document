///|
#derive(ToJson)
priv struct PdfInputLimits {
  fontBytes : Int32
  exportBytes : Int32
  rgbaBytes : Int32
  importBytes : Int32
  inkStrokeCount : Int32
  inkCoordinates : Int32
  textUnits : Int32
}

///|
let operation_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  let handlers = reading_handlers.copy()
  for
    domain in [
      page_handlers, annotation_handlers, field_handlers, object_handlers, conversion_handlers,
      redaction_handlers,
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
  mut pdf : @model.PdfSession?
  mut closed : Bool
  images : @layout.Images
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    output: @common.OutputBytes::new(),
    outlines: @common.OutlineDelta::new(),
    pdf: None,
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
  @common.encoded_response(() => {
    errdefer context.output.clear()
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let request = parse_request(input, first~, second~)
    let command : @common.OperationRequest = @common.request(request)
    let operation = command.operation
    if lifecycle_handlers.get(operation) is Some(handler) {
      return handler(context, request)
    }
    if operation_handlers.get(operation) is Some(handler) {
      guard context.pdf is Some(session) else {
        @failure.reject("session-required", "Open a PDF first")
      }
      return handler(context, session, request)
    }
    guard context.pdf is Some(_) else {
      @failure.reject("session-required", "Open a PDF first")
    }
    @failure.reject("invalid-operation", "Unknown PDF operation")
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font_wire(input, identity, font_input_bytes)
    if context.pdf is Some(session) {
      session.invalidate()
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
  if context.pdf is Some(session) {
    session.close()
  }
  context.pdf = None
  context.images.clear()
}

///|
pub fn take_output(context : Context, slot : Int32) -> String? {
  context.output.take_string(slot)
}
