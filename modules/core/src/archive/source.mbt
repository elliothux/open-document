///|
struct Source {
  size : Int32
  read_at : (Int32, Int32) -> BytesView raise @failure.Failure
}

///|
fn Source::memory(bytes : Bytes) -> Source {
  {
    size: bytes.length(),
    read_at: (offset, length) => span(bytes, offset, length),
  }
}

///|
fn Source::read(
  self : Source,
  offset : Int32,
  length : Int32,
) -> BytesView raise @failure.Failure {
  guard offset >= 0 &&
    length >= 0 &&
    offset <= self.size &&
    length <= self.size - offset else {
    @failure.reject("malformed-package", "Truncated byte range", offset~)
  }
  if length == 0 {
    return b""[:]
  }
  let bytes = (self.read_at)(offset, length)
  guard bytes.length() == length else {
    @failure.reject(
      "truncated-source",
      "Source returned an incomplete range",
      offset~,
    )
  }
  bytes
}

///|
fn Source::end_record(
  self : Source,
) -> (Int32, BytesView) raise @failure.Failure {
  guard self.size >= 22 else {
    @failure.reject("malformed-package", "Missing ZIP end record")
  }
  let last = self.size - 22
  let end = self.read(last, 22)
  if u32(end, 0) == 0x06054b50U && u16(end, 20) == 0 {
    return (last, end)
  }
  let start = (last - 65535).max(0)
  let tail = self.read(start, self.size - start)
  for cursor = last - start - 1; cursor >= 0; cursor = cursor - 1 {
    if u32(tail, cursor) == 0x06054b50U &&
      u16(tail, cursor + 20) == tail.length() - cursor - 22 {
      return (start + cursor, tail[cursor:cursor + 22])
    }
  }
  @failure.reject("malformed-package", "Missing ZIP end record")
}
