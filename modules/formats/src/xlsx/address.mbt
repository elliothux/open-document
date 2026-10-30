///|
pub(all) struct Address {
  row : Int32
  column : Int32
} derive(Eq, ToJson)

///|
pub extend Address with ToJson::{to_json}

///|
pub extend Address with Eq::{equal, not_equal}

///|
pub fn Address::parse(text : String) -> Address raise @failure.Failure {
  let mut column = 0
  let mut offset = 0
  while offset < text.length() && text[offset] >= 65 && text[offset] <= 90 {
    column = column * 26 + text[offset].to_int() - 64
    guard column <= 16384 else {
      @failure.reject("invalid-address", "Column exceeds XFD")
    }
    offset += 1
  }
  guard column > 0 && offset < text.length() && text[offset] != 48 else {
    @failure.reject("invalid-address", "Expected an A1 cell address")
  }
  let mut row = 0
  for index in offset..<text.length() {
    guard text[index] >= 48 && text[index] <= 57 else {
      @failure.reject("invalid-address", "Invalid cell row")
    }
    row = row * 10 + text[index].to_int() - 48
    guard row <= 1048576 else {
      @failure.reject("invalid-address", "Row exceeds worksheet bounds")
    }
  }
  { row, column, }
}

///|
pub fn Address::name(self : Address) -> String raise @failure.Failure {
  guard self.row >= 1 &&
    self.row <= 1048576 &&
    self.column >= 1 &&
    self.column <= 16384 else {
    @failure.reject("invalid-address", "Cell address exceeds worksheet bounds")
  }
  let mut letters = ""
  for column = self.column; column > 0; column = (column - 1) / 26 {
    letters = String::from_array([(65 + (column - 1) % 26).to_char().unwrap()]) +
      letters
  }
  letters + self.row.to_string()
}

///|
pub(all) struct Range {
  top : Int32
  left : Int32
  bottom : Int32
  right : Int32
} derive(Eq, ToJson)

///|
pub extend Range with ToJson::{to_json}

///|
pub extend Range with Eq::{equal, not_equal}

///|
pub fn Range::parse(text : String) -> Range raise @failure.Failure {
  let parts = text.split(":").collect()
  guard parts.length() == 1 || parts.length() == 2 else {
    @failure.reject("invalid-address", "Expected one rectangular range")
  }
  let first = Address::parse(parts[0].to_owned())
  let last = Address::parse(parts[parts.length() - 1].to_owned())
  guard first.row <= last.row && first.column <= last.column else {
    @failure.reject("invalid-address", "Range endpoints must be ordered")
  }
  { top: first.row, left: first.column, bottom: last.row, right: last.column, }
}

///|
fn Range::contains(self : Range, address : Address) -> Bool {
  address.row >= self.top &&
  address.row <= self.bottom &&
  address.column >= self.left &&
  address.column <= self.right
}

///|
fn Range::intersects(self : Range, other : Range) -> Bool {
  self.top <= other.bottom &&
  self.bottom >= other.top &&
  self.left <= other.right &&
  self.right >= other.left
}

///|
fn Range::name(self : Range) -> String raise @failure.Failure {
  let first : Address = { row: self.top, column: self.left, }
  let last : Address = { row: self.bottom, column: self.right, }
  if first == last {
    first.name()
  } else {
    first.name() + ":" + last.name()
  }
}

///|
// Native table/filter refs may contain absolute A1 markers. Keep the public
// address syntax strict and retain the original XML spelling when unedited.
fn native_range(text : String) -> Range raise @failure.Failure {
  let parts = text.split(":").collect()
  guard parts.length() >= 1 && parts.length() <= 2 else {
    @failure.reject("invalid-address", "Expected one rectangular range")
  }
  Range::parse(
    parts.map(part => formula_address(part.to_owned()).address.name()).join(":"),
  )
}
