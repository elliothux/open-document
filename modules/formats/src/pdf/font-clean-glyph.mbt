///|
fn clean_glyph(
  contours : Array[Array[(Double, Double, Bool)]],
) -> (Bytes, Array[Int32], Int32, Int32) raise @pdfcore.PdfError {
  let points : Array[(Int32, Int32, Bool)] = []
  let ends : Array[Int32] = []
  let bounds = [0, 0, 0, 0]
  for original in contours {
    let contour = original.copy()
    if contour.length() > 1 && contour[0] == contour[contour.length() - 1] {
      ignore(contour.pop())
    }
    let start = points.length()
    for index, (x, y, on) in contour {
      // The callback exposes implied midpoints. Omitting these preserves the
      // original quadratic contour without rounding half-unit coordinates.
      let before = contour[(index + contour.length() - 1) % contour.length()]
      let after = contour[(index + 1) % contour.length()]
      if on &&
        !before.2 &&
        !after.2 &&
        x == (before.0 + after.0) / 2 &&
        y == (before.1 + after.1) / 2 {
        continue
      }
      guard x == x.round() && y == y.round() else {
        raise @pdfcore.HardError(
          "Fractional composite outlines cannot be cleaned exactly",
        )
      }
      let x = x.to_int()
      let y = y.to_int()
      if points.is_empty() {
        bounds[0] = x
        bounds[1] = y
        bounds[2] = x
        bounds[3] = y
      } else {
        bounds[0] = bounds[0].min(x)
        bounds[1] = bounds[1].min(y)
        bounds[2] = bounds[2].max(x)
        bounds[3] = bounds[3].max(y)
      }
      points.push((x, y, on))
    }
    if points.length() > start {
      ends.push(points.length() - 1)
    }
  }
  guard points.length() <= 65535 && ends.length() <= 32767 else {
    raise @pdfcore.HardError("Clean glyph contour budget exceeded")
  }
  if points.is_empty() {
    return (b"", bounds, 0, 0)
  }
  let output : Array[Byte] = Array::make(
    12 + ends.length() * 2 + points.length() * 5,
    0,
  )
  font_put_short(output, 0, ends.length())
  for i in 0..<4 {
    font_put_short(output, 2 + i * 2, bounds[i])
  }
  for i, endpoint in ends {
    font_put_short(output, 10 + i * 2, endpoint)
  }
  // instructionLength is always zero; every coordinate has one canonical
  // signed 16-bit representation and every flag contains only ON_CURVE.
  let flags = 12 + ends.length() * 2
  let mut lastX = 0
  let mut lastY = 0
  for i, (x, y, on) in points {
    guard (x - lastX).abs() <= 32767 && (y - lastY).abs() <= 32767 else {
      raise @pdfcore.HardError("Clean glyph delta exceeds TrueType range")
    }
    output[flags + i] = if on { 1 } else { 0 }
    font_put_short(output, flags + points.length() + i * 2, x - lastX)
    font_put_short(output, flags + points.length() * 3 + i * 2, y - lastY)
    lastX = x
    lastY = y
  }
  (Bytes::from_array(output), bounds, points.length(), ends.length())
}

///|
fn clean_font_names(source : Bytes) -> Bytes raise @pdfcore.PdfError {
  let records : Array[(Int32, Int32, Int32, Int32, Bytes)] = [
    (3, 1, 0x0409, 1, utf16_bytes("Clean Font")[2:].to_owned()),
    (3, 1, 0x0409, 2, utf16_bytes("Regular")[2:].to_owned()),
    (3, 1, 0x0409, 4, utf16_bytes("Clean Font Regular")[2:].to_owned()),
    (3, 1, 0x0409, 6, utf16_bytes("CleanFont-Regular")[2:].to_owned()),
  ]
  // Copyright and license terms are required font assets, not document data.
  // All identity, unique-ID, author, URL and custom names are discarded.
  if font_table(source, 0x6e616d65U) is Some(names) && names.length() >= 6 {
    let count = font_short(names, 2)
    let storage = font_short(names, 4)
    guard count <= 1024 && 6 + count * 12 <= names.length() else {
      raise @pdfcore.HardError("Malformed font license names")
    }
    for index in 0..<count {
      let entry = 6 + index * 12
      let id = font_short(names, entry + 6)
      let platform = font_short(names, entry)
      if id == 0 || id == 13 || id == 14 {
        let encoding = font_short(names, entry + 2)
        let language = font_short(names, entry + 4)
        guard platform == 0 || platform == 1 || platform == 3 else {
          raise @pdfcore.HardError(
            "Font license uses an unsupported name platform",
          )
        }
        let length = font_short(names, entry + 8)
        let offset = storage + font_short(names, entry + 10)
        guard offset + length <= names.length() else {
          raise @pdfcore.HardError("Malformed font license text")
        }
        let data = names[offset:offset + length].to_owned()
        if !records.any(record => {
            record.0 == platform &&
            record.1 == encoding &&
            record.2 == language &&
            record.3 == id &&
            record.4 == data
          }) {
          records.push((platform, encoding, language, id, data))
        }
      }
    }
  }
  let mut size = 6 + records.length() * 12
  for (_, _, _, _, data) in records {
    size += data.length()
  }
  guard size <= 65535 else {
    raise @pdfcore.HardError("Font license names exceed clean budget")
  }
  let output : Array[Byte] = Array::make(size, 0)
  font_put_short(output, 2, records.length())
  let storage = 6 + records.length() * 12
  font_put_short(output, 4, storage)
  let mut offset = storage
  for index, (platform, encoding, language, id, data) in records {
    let entry = 6 + index * 12
    font_put_short(output, entry, platform)
    font_put_short(output, entry + 2, encoding)
    font_put_short(output, entry + 4, language)
    font_put_short(output, entry + 6, id)
    font_put_short(output, entry + 8, data.length())
    font_put_short(output, entry + 10, offset - storage)
    for i in 0..<data.length() {
      output[offset + i] = data[i]
    }
    offset += data.length()
  }
  Bytes::from_array(output)
}
