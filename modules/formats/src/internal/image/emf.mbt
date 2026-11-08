///|
fn emf_uint(
  bytes : Bytes,
  offset : Int32,
  size : Int32,
) -> Int32 raise @failure.Failure {
  guard offset >= 0 && size <= bytes.length() - offset else {
    @failure.reject("invalid-image", "Truncated EMF field")
  }
  let mut value = 0
  for i in 0..<size {
    value = value | (bytes[offset + i].to_int() << (i * 8))
  }
  value
}

///|
fn emf_color(value : Int32) -> String raise @failure.Failure {
  guard value >= 0 && [0, 2].contains(value >> 24) else {
    @failure.reject("unsupported-image", "EMF palette colors require a palette")
  }
  let out = StringBuilder()
  for shift in [0, 8, 16] {
    let channel = (value >> shift) & 255
    out.write_char("0123456789abcdef"[channel >> 4].to_char().unwrap())
    out.write_char("0123456789abcdef"[channel & 15].to_char().unwrap())
  }
  out.to_string()
}

///|
fn emf_rect(
  bytes : Bytes,
  offset : Int32,
) -> @layout.Border raise @failure.Failure {
  let x = emf_uint(bytes, offset, 4).to_double()
  let y = emf_uint(bytes, offset + 4, 4).to_double()
  {
    x,
    y,
    width: emf_uint(bytes, offset + 8, 4).to_double() - x,
    height: emf_uint(bytes, offset + 12, 4).to_double() - y,
  }
}

///|
fn emf_string(
  bytes : Bytes,
  offset : Int32,
  units : Int32,
) -> String raise @failure.Failure {
  guard units >= 0 &&
    units <= 32767 &&
    offset >= 0 &&
    units <= (bytes.length() - offset) / 2 else {
    @failure.reject("invalid-image", "Invalid EMF string bounds")
  }
  @utf16.decode(
    bytes[offset:offset + units * 2],
    ignore_bom=true,
    endianness=@utf16.Little,
  ) catch {
    _ => @failure.reject("invalid-image", "Invalid EMF Unicode text")
  }
}

///|
fn emf_bitmap(
  record : Bytes,
  key : String,
) -> @layout.MetafileCommand raise @failure.Failure {
  let bmi = emf_uint(record, 84, 4)
  let bmi_size = emf_uint(record, 88, 4)
  let bits = emf_uint(record, 92, 4)
  let bits_size = emf_uint(record, 96, 4)
  guard bmi >= 108 &&
    bmi_size >= 40 &&
    bmi_size <= record.length() - bmi &&
    bits >= bmi + bmi_size &&
    bits_size >= 0 &&
    bits_size <= record.length() - bits &&
    emf_uint(record, bmi, 4) == 40 &&
    emf_uint(record, bmi + 12, 2) == 1 &&
    emf_uint(record, bmi + 14, 2) == 32 &&
    [0, 3].contains(emf_uint(record, bmi + 16, 4)) &&
    emf_uint(record, 80, 4) == 0 &&
    emf_uint(record, 52, 4) == 0x3f800000 &&
    emf_uint(record, 56, 4) == 0 &&
    emf_uint(record, 60, 4) == 0 &&
    emf_uint(record, 64, 4) == 0x3f800000 &&
    emf_uint(record, 68, 4) == 0 &&
    emf_uint(record, 72, 4) == 0 &&
    emf_uint(record, 44, 4) == 0 &&
    emf_uint(record, 48, 4) == 0 else {
    @failure.reject(
      "unsupported-image", "EMF bitmap requires an untransformed 32-bit RGB source",
    )
  }
  if emf_uint(record, bmi + 16, 4) == 3 {
    guard bmi_size >= 52 &&
      emf_uint(record, bmi + 40, 4) == 0xff0000 &&
      emf_uint(record, bmi + 44, 4) == 0xff00 &&
      emf_uint(record, bmi + 48, 4) == 0xff else {
      @failure.reject(
        "unsupported-image", "Unsupported EMF bitmap channel masks",
      )
    }
  }
  let width = emf_uint(record, bmi + 4, 4)
  let signed_height = emf_uint(record, bmi + 8, 4)
  guard width > 0 && width <= 4096 && signed_height != -2147483648 else {
    @failure.reject("limit-exceeded", "EMF bitmap dimensions exceed budget")
  }
  let height = signed_height.abs()
  guard height > 0 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() <= 4194304 &&
    width * height * 4 <= bits_size &&
    emf_uint(record, 100, 4) == width &&
    emf_uint(record, 104, 4) == height else {
    @failure.reject("invalid-image", "Invalid EMF bitmap dimensions or crop")
  }
  let blend = emf_uint(record, 40, 4)
  // MS-EMF 2.3.1.1 requires readers to ignore BlendFlags, including legacy nonzero bytes.
  guard (blend & 255) == 0 && [0, 1].contains((blend >> 24) & 255) else {
    @failure.reject(
      "unsupported-image", "Unsupported EMF bitmap blend function",
    )
  }
  let alpha = (blend >> 16) & 255
  let source_alpha = ((blend >> 24) & 255) == 1
  let rgba : Array[Byte] = Array::make(width * height * 4, 0)
  for y in 0..<height {
    let row = if signed_height < 0 { y } else { height - 1 - y }
    for x in 0..<width {
      let source = bits + (row * width + x) * 4
      let target = (y * width + x) * 4
      let a = if source_alpha { record[source + 3].to_int() } else { 255 }
      for index, channel in [2, 1, 0] {
        let value = record[source + channel].to_int()
        guard !source_alpha || value <= a else {
          @failure.reject(
            "invalid-image", "EMF alpha bitmap is not premultiplied",
          )
        }
        rgba[target + index] = (if source_alpha && a > 0 {
          (value * 255 + a / 2) / a
        } else {
          value
        }).to_byte()
      }
      rgba[target + 3] = ((a * alpha + 127) / 255).to_byte()
    }
  }
  let rect : @layout.Border = {
    x: emf_uint(record, 24, 4).to_double(),
    y: emf_uint(record, 28, 4).to_double(),
    width: emf_uint(record, 32, 4).to_double(),
    height: emf_uint(record, 36, 4).to_double(),
  }
  @layout.Bitmap(key, rect, width, height, Bytes::from_array(rgba))
}

///|
// ONLYOFFICE CEmfParserBase::HANDLE_EMR_HEADER derives logical bounds from the physical frame.
// shortcut: Native EMF accepts solid GDI paths, horizontal text and RGB alpha bitmaps; extend unsupported drawing records when required.
pub fn read_emf(bytes : Bytes) -> @layout.Metafile raise @failure.Failure {
  guard bytes.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "EMF input exceeds budget")
  }
  guard bytes.length() >= 88 &&
    emf_uint(bytes, 0, 4) == 1 &&
    emf_uint(bytes, 40, 4) == 0x464d4520 &&
    emf_uint(bytes, 44, 4) == 0x10000 &&
    emf_uint(bytes, 48, 4) == bytes.length() else {
    @failure.reject("invalid-image", "Invalid EMF header")
  }
  let expected = emf_uint(bytes, 52, 4)
  let handles = emf_uint(bytes, 56, 2)
  guard expected >= 2 && expected <= 8192 && handles > 0 && handles <= 256 else {
    @failure.reject(
      "limit-exceeded", "EMF record or object count exceeds budget",
    )
  }
  let frame = emf_rect(bytes, 24)
  let device_x = emf_uint(bytes, 72, 4).to_double()
  let device_y = emf_uint(bytes, 76, 4).to_double()
  let millimeters_x = emf_uint(bytes, 80, 4).to_double()
  let millimeters_y = emf_uint(bytes, 84, 4).to_double()
  guard [device_x, device_y, millimeters_x, millimeters_y].all(v => {
    v > 0 && v <= 10000000
  }) else {
    @failure.reject("invalid-image", "Invalid EMF device dimensions")
  }
  let bounds : @layout.Border = {
    x: (frame.x / 100 / millimeters_x * device_x + 0.5).floor(),
    y: (frame.y / 100 / millimeters_y * device_y + 0.5).floor(),
    width: (frame.width / 100 / millimeters_x * device_x + 0.5).floor(),
    height: (frame.height / 100 / millimeters_y * device_y + 0.5).floor(),
  }
  let hash = StringBuilder()
  for byte in @crypto.sha256(bytes) {
    hash.write_char("0123456789abcdef"[byte.to_int() >> 4].to_char().unwrap())
    hash.write_char("0123456789abcdef"[byte.to_int() & 15].to_char().unwrap())
  }
  let identity = "emf:" + hash.to_string()
  let reader = EmfReader::new(handles)
  let mut at = 0
  let mut count = 0
  let mut done = false
  while at < bytes.length() {
    let kind = emf_uint(bytes, at, 4)
    let size = emf_uint(bytes, at + 4, 4)
    guard !done &&
      size >= 8 &&
      size % 4 == 0 &&
      size <= bytes.length() - at &&
      count < expected else {
      @failure.reject("invalid-image", "Invalid EMF record bounds or count")
    }
    let record = bytes[at:at + size].to_owned()
    match kind {
      1 => {
        guard at == 0 &&
          size >= 88 &&
          emf_uint(record, 60, 4) == 0 &&
          emf_uint(record, 68, 4) == 0 &&
          (size < 100 || emf_uint(record, 96, 4) == 0) else {
          @failure.reject(
            "unsupported-image", "Extended EMF header requires support",
          )
        }
      }
      14 => {
        guard size == 20 &&
          emf_uint(record, 8, 4) == 0 &&
          emf_uint(record, 16, 4) == 20 else {
          @failure.reject("unsupported-image", "EMF palette requires support")
        }
        done = true
      }
      114 => {
        let world = reader.dc.world
        guard world.a == 1 &&
          world.b == 0 &&
          world.c == 0 &&
          world.d == 1 &&
          world.e == 0 &&
          world.f == 0 &&
          reader.dc.clip is None else {
          @failure.reject(
            "unsupported-image", "Transformed EMF bitmap requires support",
          )
        }
        reader.commands.push(emf_bitmap(record, identity + ":\{count}"))
      }
      _ => {
        guard reader.state_record(kind, record) ||
          reader.path_record(kind, record) else {
          @failure.reject(
            "unsupported-image",
            "Unsupported EMF record: \{kind}",
          )
        }
      }
    }
    at += size
    count += 1
  }
  guard done &&
    count == expected &&
    reader.stack.is_empty() &&
    !reader.path_open &&
    !reader.path_ready &&
    (!reader.plus_started || reader.plus_done) else {
    @failure.reject("invalid-image", "Incomplete EMF records or drawing state")
  }
  @layout.Metafile::new(bounds, reader.commands)
}
