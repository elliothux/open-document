///|
/// A plain-text editing probe, not an Office document model.
pub struct Session {
  priv mut text : String
  priv history : Array[String]
  priv mut closed : Bool
}

///|
pub fn Session::new(text : String) -> Session {
  { text, history: [], closed: false, }
}

///|
pub fn Session::content(self : Session) -> String {
  self.text
}

///|
/// Replace a UTF-16 range without splitting a surrogate pair.
/// Status: 0 success, 1 invalid range, 2 closed, 3 history budget exceeded.
pub fn Session::replace(
  self : Session,
  start : Int,
  end : Int,
  replacement : String,
) -> Int {
  if self.closed {
    return 2
  }
  if start < 0 || end < start || end > self.text.length() {
    return 1
  }
  guard self.text.get_view(end=start) is Some(before) else { return 1 }
  guard self.text.get_view(start=end) is Some(after) else { return 1 }
  // P0 probe: bound snapshot undo; replace with edit records in the editor phase.
  if self.history.length() >= 100 {
    return 3
  }
  self.history.push(self.text)
  self.text = before.to_owned() + replacement + after.to_owned()
  0
}

///|
/// Status: 0 success, 2 closed, 4 no undo history.
pub fn Session::undo(self : Session) -> Int {
  if self.closed {
    return 2
  }
  match self.history.pop() {
    Some(previous) => {
      self.text = previous
      0
    }
    None => 4
  }
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.text = ""
  self.history.clear()
  self.closed = true
}
