///|
pub fn open_text(text : String) -> @text.Session {
  @text.Session::new(text)
}

///|
pub fn read_text(session : @text.Session) -> String {
  session.content()
}

///|
pub fn replace_text(
  session : @text.Session,
  start : Int,
  end : Int,
  replacement : String,
) -> Int {
  session.replace(start, end, replacement)
}

///|
pub fn undo(session : @text.Session) -> Int {
  session.undo()
}

///|
pub fn close(session : @text.Session) -> Unit {
  session.close()
}
