///|
pub struct Context {
  probe : @layout.TextProbe
  mut pdf : @model.PdfSession?
  mut closed : Bool
  images : @layout.Images
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    pdf: None,
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
    context.pdf_operation(operation, request)
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font(font_input_bytes(input), identity)
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
  context.probe.close()
  if context.pdf is Some(session) {
    session.close()
  }
  context.pdf = None
  context.images.clear()
}
