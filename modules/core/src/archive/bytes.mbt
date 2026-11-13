///|
fn span(
  data : BytesView,
  offset : Int32,
  size : Int32,
) -> BytesView raise @failure.Failure {
  guard offset >= 0 &&
    size >= 0 &&
    offset <= data.length() &&
    size <= data.length() - offset else {
    @failure.reject("malformed-package", "Truncated byte range", offset~)
  }
  data[offset:offset + size]
}

///|
fn u16(data : BytesView, offset : Int32) -> Int32 raise @failure.Failure {
  let bytes = span(data, offset, 2)
  bytes[0].to_int() | (bytes[1].to_int() << 8)
}

///|
fn u32(data : BytesView, offset : Int32) -> UInt32 raise @failure.Failure {
  let bytes = span(data, offset, 4)
  bytes[0].to_uint() |
  (bytes[1].to_uint() << 8) |
  (bytes[2].to_uint() << 16) |
  (bytes[3].to_uint() << 24)
}

///|
fn size32(
  data : BytesView,
  offset : Int32,
  base~ : Int32 = 0,
) -> Int32 raise @failure.Failure {
  let value = u32(data, offset)
  guard value <= 0x7fffffffU else {
    @failure.reject(
      "unsupported-package",
      "ZIP64 or size outside i32 range",
      offset=base + offset,
    )
  }
  value.reinterpret_as_int()
}

///|
fn zip64_extra(
  data : BytesView,
  offset : Int32,
  size : Int32,
  base~ : Int32 = 0,
) -> BytesView? raise @failure.Failure {
  ignore(span(data, offset, size))
  let end = offset + size
  let mut zip64 = None
  for cursor = offset; cursor < end; {
    guard end - cursor >= 4 else {
      @failure.reject(
        "malformed-package",
        "Truncated ZIP extra field",
        offset=base + cursor,
      )
    }
    let length = u16(data, cursor + 2)
    guard length <= end - cursor - 4 else {
      @failure.reject(
        "malformed-package",
        "Invalid ZIP extra field length",
        offset=base + cursor,
      )
    }
    if u16(data, cursor) == 1 {
      guard zip64 is None else {
        @failure.reject(
          "malformed-package",
          "Duplicate ZIP64 extra field",
          offset=base + cursor,
        )
      }
      zip64 = Some(data[cursor + 4:cursor + 4 + length])
    }
    continue cursor + 4 + length
  }
  zip64
}

///|
fn put16(out : FixedArray[Byte], offset : Int32, value : Int32) -> Unit {
  out[offset] = value.to_byte()
  out[offset + 1] = (value >> 8).to_byte()
}

///|
fn put32(out : FixedArray[Byte], offset : Int32, value : UInt32) -> Unit {
  for i in 0..<4 {
    out[offset + i] = (value >> (i * 8)).to_byte()
  }
}
