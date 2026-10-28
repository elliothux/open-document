///|
pub struct Context {
  probe : @layout.TextProbe
  mut docx : @model.Session?
  mut closed : Bool
  images : @layout.Images
  mut layout_id : Int
  mut layout : @layout.Layout?
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    docx: None,
    closed: false,
    images: @layout.Images::new(),
    layout_id: 0,
    layout: None,
  }
}

///|
pub fn call(context : Context, input : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let request = parse_request(input)
    context.dispatch(request)
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font(font_input_bytes(input), identity)
    context.layout = None
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
  if context.docx is Some(session) {
    session.close()
  }
  context.docx = None
  context.layout = None
  context.images.clear()
}
