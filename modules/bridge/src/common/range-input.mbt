///|
pub struct RangeInput {
  priv ranges : Map[(Int32, Int32), Bytes]
  priv mut retained : Int32
  priv mut needed : (Int32, Int32)?
}

///|
pub fn RangeInput::new() -> RangeInput {
  { ranges: Map([]), retained: 0, needed: None, }
}

///|
pub fn RangeInput::read(
  self : RangeInput,
  offset : Int32,
  length : Int32,
) -> BytesView raise @failure.Failure {
  if self.ranges.get((offset, length)) is Some(bytes) {
    return bytes[:]
  }
  if self.needed is None {
    self.needed = Some((offset, length))
  }
  self.require_ranges()
  @failure.reject("truncated-source", "Source range is unavailable", offset~)
}

///|
pub fn RangeInput::require_ranges(
  self : RangeInput,
) -> Unit raise @failure.Failure {
  if self.needed is Some((offset, length)) {
    // The host supplies this internal range before retrying the operation.
    @failure.reject(
      "source-range-required",
      "Source range required",
      part=length.to_string(),
      offset~,
    )
  }
}

///|
pub fn RangeInput::clear(self : RangeInput) -> Unit {
  self.ranges.clear()
  self.retained = 0
  self.needed = None
}

///|
pub fn RangeInput::supply(
  self : RangeInput,
  input : String,
) -> Unit raise @failure.Failure {
  guard self.needed is Some((offset, length)) else {
    @failure.reject("invalid-operation", "No pending source range")
  }
  guard length <= 64 * 1024 * 1024 - self.retained else {
    @failure.reject("limit-exceeded", "Source range budget exceeded", offset~)
  }
  let bytes = byte_input(input, length)
  guard bytes.length() == length else {
    @failure.reject("truncated-source", "Incomplete source range", offset~)
  }
  self.ranges[(offset, length)] = bytes
  self.retained += length
  self.needed = None
}
