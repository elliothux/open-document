///|
fn span(
  data : Bytes,
  offset : Int,
  size : Int,
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
fn u16(data : Bytes, offset : Int) -> Int raise @failure.Failure {
  let bytes = span(data, offset, 2)
  bytes[0].to_int() | (bytes[1].to_int() << 8)
}

///|
fn u32(data : Bytes, offset : Int) -> UInt raise @failure.Failure {
  let bytes = span(data, offset, 4)
  bytes[0].to_uint() |
  (bytes[1].to_uint() << 8) |
  (bytes[2].to_uint() << 16) |
  (bytes[3].to_uint() << 24)
}

///|
fn size32(data : Bytes, offset : Int) -> Int raise @failure.Failure {
  let value = u32(data, offset)
  guard value <= 0x7fffffffU else {
    @failure.reject(
      "unsupported-package",
      "ZIP64 or size outside i32 range",
      offset~,
    )
  }
  value.reinterpret_as_int()
}

///|
fn extra(data : Bytes, offset : Int, size : Int) -> Unit raise @failure.Failure {
  ignore(span(data, offset, size))
  let end = offset + size
  for cursor = offset; cursor < end; {
    guard end - cursor >= 4 else {
      @failure.reject(
        "malformed-package",
        "Truncated ZIP extra field",
        offset=cursor,
      )
    }
    guard u16(data, cursor) != 1 else {
      @failure.reject(
        "unsupported-package",
        "ZIP64 is unsupported",
        offset=cursor,
      )
    }
    let length = u16(data, cursor + 2)
    guard length <= end - cursor - 4 else {
      @failure.reject(
        "malformed-package",
        "Invalid ZIP extra field length",
        offset=cursor,
      )
    }
    continue cursor + 4 + length
  }
}

///|
fn put16(out : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  out[offset] = value.to_byte()
  out[offset + 1] = (value >> 8).to_byte()
}

///|
fn put32(out : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  for i in 0..<4 {
    out[offset + i] = (value >> (i * 8)).to_byte()
  }
}
