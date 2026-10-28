///|
fn font_word(bytes : Bytes, offset : Int32) -> UInt32 {
  (bytes[offset].to_int().reinterpret_as_uint() << 24) |
  (bytes[offset + 1].to_int().reinterpret_as_uint() << 16) |
  (bytes[offset + 2].to_int().reinterpret_as_uint() << 8) |
  bytes[offset + 3].to_int().reinterpret_as_uint()
}

///|
fn font_short(bytes : Bytes, offset : Int32) -> Int32 {
  bytes[offset].to_int() * 256 + bytes[offset + 1].to_int()
}

///|
fn font_put_short(output : Array[Byte], offset : Int32, value : Int32) -> Unit {
  output[offset] = (value >> 8).to_byte()
  output[offset + 1] = (value & 255).to_byte()
}

///|
fn font_put_word(output : Array[Byte], offset : Int32, value : UInt32) -> Unit {
  for i in 0..<4 {
    output[offset + i] = (value >> ((3 - i) * 8)).reinterpret_as_int().to_byte()
  }
}

///|
fn font_checksum(bytes : Bytes) -> UInt32 {
  let mut sum = 0U
  for offset = 0; offset < bytes.length(); offset = offset + 4 {
    let mut value = 0U
    for i in 0..<4 {
      value = (value << 8) |
        (if offset + i < bytes.length() {
          bytes[offset + i].to_int().reinterpret_as_uint()
        } else {
          0U
        })
    }
    sum += value
  }
  sum
}

///|
fn font_table(bytes : Bytes, tag : UInt32) -> Bytes? {
  if bytes.length() < 12 {
    return None
  }
  let count = font_short(bytes, 4)
  if count > 128 || 12 + count * 16 > bytes.length() {
    return None
  }
  for index in 0..<count {
    let entry = 12 + index * 16
    if font_word(bytes, entry) == tag {
      let offset = font_word(bytes, entry + 8).to_uint64()
      let length = font_word(bytes, entry + 12).to_uint64()
      if offset + length > bytes.length().to_uint64() {
        return None
      }
      return Some(
        bytes[offset.to_int():offset.to_int() + length.to_int()].to_owned(),
      )
    }
  }
  None
}

///|
/// The pinned subsetter deliberately omits OS/2. Retain only original embedding
/// policy, style and line metrics, without old Unicode/code-page ranges.
fn subset_font_policy(
  subset : Bytes,
  source : Bytes,
) -> Bytes raise @pdfcore.PdfError {
  guard font_table(source, 0x4f532f32U) is Some(policy) && policy.length() >= 78 else {
    raise @pdfcore.HardError("Font embedding policy is unavailable")
  }
  guard (font_short(policy, 8) & 0x0302) == 0 else {
    raise @pdfcore.HardError("Font embedding or subsetting is restricted")
  }
  let minimal = Bytes::makei(78, i => {
    if i >= 64 && i < 68 {
      255
    } else if i >= 58 && i < 62 {
      b"NONE"[i - 58]
    } else if (i >= 2 && i < 42) || (i >= 62 && i < 64) || i >= 68 {
      policy[i]
    } else {
      0
    }
  })
  guard subset.length() >= 12 && subset[0:4] == b"\x00\x01\x00\x00" else {
    raise @pdfcore.HardError("Font subset must be TrueType")
  }
  let count = font_short(subset, 4)
  guard count > 0 && count <= 128 && 12 + count * 16 <= subset.length() else {
    raise @pdfcore.HardError("Font subset directory is malformed")
  }
  let tables : Array[(UInt32, Bytes)] = [(0x4f532f32U, minimal)]
  for index in 0..<count {
    let entry = 12 + index * 16
    let tag = font_word(subset, entry)
    if tag == 0x4f532f32U {
      continue
    }
    guard font_table(subset, tag) is Some(data) else {
      raise @pdfcore.HardError("Font subset table is malformed")
    }
    let data = if tag == 0x68656164U {
      guard data.length() >= 12 else {
        raise @pdfcore.HardError("Font subset head is malformed")
      }
      Bytes::makei(data.length(), i => {
        if i >= 8 && i < 12 {
          0
        } else {
          data[i]
        }
      })
    } else {
      data
    }
    tables.push((tag, data))
  }
  font_construct(tables)
}

///|
fn font_construct(
  tables : Array[(UInt32, Bytes)],
) -> Bytes raise @pdfcore.PdfError {
  for index, (tag, data) in tables {
    if tag == 0x68656164U {
      guard data.length() >= 12 else {
        raise @pdfcore.HardError("Malformed font head")
      }
      tables[index] = (
        tag,
        Bytes::makei(data.length(), i => {
          if i >= 8 && i < 12 {
            0
          } else {
            data[i]
          }
        }),
      )
    }
  }
  tables.sort_by((a, b) => a.0.compare(b.0))
  let mut size = 12 + tables.length() * 16
  for (_, data) in tables {
    size += (data.length() + 3) / 4 * 4
  }
  guard size <= 33554432 else {
    raise @pdfcore.HardError("Font subset exceeds policy budget")
  }
  let output : Array[Byte] = Array::make(size, 0)
  output[1] = 1
  font_put_short(output, 4, tables.length())
  let mut power = 1
  let mut selector = 0
  while power * 2 <= tables.length() {
    power *= 2
    selector += 1
  }
  font_put_short(output, 6, power * 16)
  font_put_short(output, 8, selector)
  font_put_short(output, 10, tables.length() * 16 - power * 16)
  let mut offset = 12 + tables.length() * 16
  let mut head = -1
  for index, (tag, data) in tables {
    let entry = 12 + index * 16
    font_put_word(output, entry, tag)
    font_put_word(output, entry + 4, font_checksum(data))
    font_put_word(output, entry + 8, offset.reinterpret_as_uint())
    font_put_word(output, entry + 12, data.length().reinterpret_as_uint())
    for i in 0..<data.length() {
      output[offset + i] = data[i]
    }
    if tag == 0x68656164U {
      head = offset
    }
    offset += (data.length() + 3) / 4 * 4
  }
  guard head >= 0 else {
    raise @pdfcore.HardError("Font subset head is missing")
  }
  font_put_word(
    output,
    head + 8,
    0xb1b0afbaU - font_checksum(Bytes::from_array(output)),
  )
  Bytes::from_array(output)
}
