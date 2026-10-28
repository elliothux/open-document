///|
fn png_u32(output : Array[Byte], value : UInt32) -> Unit {
  for shift in [24, 16, 8, 0] {
    output.push((value >> shift).to_byte())
  }
}

///|
fn png_chunk(output : Array[Byte], kind : Bytes, payload : Bytes) -> Unit {
  png_u32(output, payload.length().reinterpret_as_uint())
  output.append(kind.to_array())
  output.append(payload.to_array())
  let checksum = @checksum.Crc32()
  checksum.update(kind)
  checksum.update(payload)
  png_u32(output, checksum.finish())
}

///|
/// Encode bounded, decoded RGBA pixels into a PNG resource for native Office parts.
pub fn encode_png(
  width : Int32,
  height : Int32,
  rgba : Bytes,
) -> Bytes raise @failure.Failure {
  guard width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() * 4 == rgba.length().to_int64() &&
    rgba.length() <= 16777216 else {
    @failure.reject("invalid-image", "PNG output requires bounded RGBA pixels")
  }
  let header : Array[Byte] = []
  png_u32(header, width.reinterpret_as_uint())
  png_u32(header, height.reinterpret_as_uint())
  header.append([8, 6, 0, 0, 0])
  let stride = width * 4
  let filtered = Bytes::makei((stride + 1) * height, index => {
    if index % (stride + 1) == 0 {
      b'\x00'
    } else {
      rgba[index / (stride + 1) * stride + index % (stride + 1) - 1]
    }
  })
  let deflated = @flate.deflate_all(filtered)
  let zlib : Array[Byte] = [0x78, 0x9c]
  zlib.append(deflated.to_array())
  png_u32(zlib, @checksum.adler32(filtered))
  let output : Array[Byte] = [137, 80, 78, 71, 13, 10, 26, 10]
  png_chunk(output, b"IHDR", Bytes::from_array(header))
  png_chunk(output, b"IDAT", Bytes::from_array(zlib))
  png_chunk(output, b"IEND", b"")
  Bytes::from_array(output)
}
