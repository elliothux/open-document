///|
fn jbig2_arithmetic_region(
  bytes : Bytes,
  width : Int32,
  height : Int32,
  flags : Int32,
) -> Bytes raise {
  // shortcut: decode template zero without row prediction; protect other arithmetic modes.
  guard flags == 0 else {
    @failure.reject("unsupported-pdf", "Unsupported JBIG2 arithmetic template")
  }
  guard bytes.length() >= 12 && bytes[bytes.length() - 2:] == b"\xff\xac" else {
    @failure.reject("invalid-pdf", "Truncated JBIG2 arithmetic region")
  }
  let neighbors = [
    (-1, -2),
    (0, -2),
    (1, -2),
    (-2, -1),
    (-1, -1),
    (0, -1),
    (1, -1),
    (2, -1),
    (-4, 0),
    (-3, 0),
    (-2, 0),
    (-1, 0),
  ]
  for i in 0..<4 {
    let x = bytes[i * 2].to_int()
    let y = bytes[i * 2 + 1].to_int()
    let x = if x >= 128 { x - 256 } else { x }
    let y = if y >= 128 { y - 256 } else { y }
    guard y < 0 || (y == 0 && x < 0) else {
      @failure.reject(
        "invalid-pdf", "JBIG2 adaptive pixels must precede the current pixel",
      )
    }
    neighbors.push((x, y))
  }
  let stride = (width + 7) / 8
  @pdfcore.sdk_decoded(65536 * 4 + stride * height)
  let output : Array[Byte] = Array::make(stride * height, 0)
  let decoder : ImageArithmetic = {
    bytes: bytes[8:].to_owned(),
    states: Array::make(65536, 0),
    offset: 0,
    interval: 0x80000000U,
    code: (bytes[8].to_uint() ^ 255U) << 16,
    remaining: 0,
  }
  decoder.refill()
  decoder.code = decoder.code << 7
  decoder.remaining -= 7
  for y in 0..<height {
    @pdfcore.sdk_check(1)
    for x in 0..<width {
      @pdfcore.sdk_check(17)
      let mut context = 0
      for (dx, dy) in neighbors {
        let nx = x + dx
        let ny = y + dy
        let bit = if nx < 0 || nx >= width || ny < 0 {
          0
        } else {
          (output[ny * stride + nx / 8].to_int() >> (7 - nx % 8)) & 1
        }
        context = (context << 1) | bit
      }
      if decoder.bit(context) == 1 {
        let at = y * stride + x / 8
        output[at] = output[at] | (1 << (7 - x % 8)).to_byte()
      }
    }
  }
  Bytes::from_array(output)
}
