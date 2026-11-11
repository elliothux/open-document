///|
#derive(ToJson)
priv struct DocxInputLimits {
  fontBytes : Int32
  exportBytes : Int32
  imageBytes : Int32
  rgbaBytes : Int32
  inkPoints : Int32
  markupSourceUnits : Int32
  clipboardFragmentUnits : Int32
  textCommandUnits : Int32
  revisionEntries : Int32
}

///|
let session_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  let handlers = input_handlers.copy()
  for
    domain in [
      view_handlers, clipboard_handlers, search_handlers, format_handlers, page_handlers,
      domain_handlers, note_handlers,
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
  mut docx : @model.Session?
  mut closed : Bool
  images : @layout.Images
  mut layout_id : Int32
  mut layout : @layout.Layout?
}

///|
pub fn new_context() -> Context {
  {
    probe: @layout.TextProbe::new(),
    output: @common.OutputBytes::new(),
    outlines: @common.OutlineDelta::new(),
    docx: None,
    closed: false,
    images: @layout.Images::new(),
    layout_id: 0,
    layout: None,
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
    context.outlines.drawing(context.dispatch(request))
  })
}

///|
pub fn add_font(context : Context, input : String, identity : String) -> String {
  response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Session is closed")
    }
    let index = context.probe.add_font_wire(input, identity, font_input_bytes)
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
  context.output.clear()
  context.outlines.clear()
  context.probe.close()
  if context.docx is Some(session) {
    session.close()
  }
  context.docx = None
  context.layout = None
  context.images.clear()
}

///|
pub fn take_output(context : Context, slot : Int32) -> String? {
  context.output.take_string(slot)
}
