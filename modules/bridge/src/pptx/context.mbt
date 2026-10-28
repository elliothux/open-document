///|
pub struct Context {
  probe : @layout.TextProbe
  mut pptx : @model.Session?
  mut closed : Bool
  images : @layout.Images
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    pptx: None,
    closed: false,
    images: @layout.Images::new(),
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
    context.pptx_operation(operation, request)
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font(font_input_bytes(input), identity)
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
  context.probe.close()
  if context.pptx is Some(session) {
    session.close()
  }
  context.pptx = None
  context.images.clear()
}
