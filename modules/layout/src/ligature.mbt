///|
fn caret_u16(data : BytesView, offset : Int) -> Int raise @failure.Failure {
  guard offset >= 0 && offset <= data.length() - 2 else {
    @failure.reject("malformed-font", "Truncated GDEF caret table")
  }
  data[offset].to_int() * 256 + data[offset + 1].to_int()
}

///|
fn caret_coverage(
  data : BytesView,
  offset : Int,
  glyph : UInt,
) -> Int? raise @failure.Failure {
  let format = caret_u16(data, offset)
  let count = caret_u16(data, offset + 2)
  let stride = if format == 1 { 2 } else { 6 }
  guard (format == 1 || format == 2) &&
    offset + 4 + count * stride <= data.length() else {
    @failure.reject("malformed-font", "Invalid GDEF caret coverage")
  }
  for i in 0..<count {
    let base = offset + 4 + i * stride
    let first = caret_u16(data, base)
    if format == 1 {
      if glyph == first.reinterpret_as_uint() {
        return Some(i)
      }
    } else {
      let last = caret_u16(data, base + 2)
      guard first <= last else {
        @failure.reject("malformed-font", "Reversed GDEF coverage range")
      }
      if glyph >= first.reinterpret_as_uint() &&
        glyph <= last.reinterpret_as_uint() {
        return Some(
          caret_u16(data, base + 4) + glyph.reinterpret_as_int() - first,
        )
      }
    }
  }
  None
}

///|
// The pinned shaper exposes GDEF headers but no LigCaretList reader.
fn ligature_values(
  data : BytesView,
  list : Int,
  glyph : UInt,
) -> Array[(Int, Int)] raise @failure.Failure {
  let coverage = caret_u16(data, list)
  let count = caret_u16(data, list + 2)
  guard coverage > 0 && list + 4 + count * 2 <= data.length() else {
    @failure.reject("malformed-font", "Invalid GDEF ligature list")
  }
  guard caret_coverage(data, list + coverage, glyph) is Some(index) else {
    return []
  }
  guard index < count else {
    @failure.reject("malformed-font", "GDEF coverage exceeds ligature list")
  }
  let relative = caret_u16(data, list + 4 + index * 2)
  guard relative > 0 else {
    @failure.reject("malformed-font", "Missing GDEF ligature record")
  }
  let base = list + relative
  let count = caret_u16(data, base)
  guard base + 2 + count * 2 <= data.length() else {
    @failure.reject("malformed-font", "Truncated GDEF caret offsets")
  }
  let values : Array[(Int, Int)] = []
  for i in 0..<count {
    let relative = caret_u16(data, base + 2 + i * 2)
    guard relative > 0 else {
      @failure.reject("malformed-font", "Missing GDEF caret value")
    }
    let format = caret_u16(data, base + relative)
    let value = caret_u16(data, base + relative + 2)
    guard format >= 1 && format <= 3 else {
      @failure.reject("malformed-font", "Unknown GDEF caret value format")
    }
    if format == 3 {
      // Device adjustments do not apply to the unhinted default-variation layout.
      let device = caret_u16(data, base + relative + 4)
      if device > 0 {
        ignore(caret_u16(data, base + relative + device + 4))
      }
    }
    values.push(
      (
        format,
        if format != 2 && value >= 32768 {
          value - 65536
        } else {
          value
        },
      ),
    )
  }
  values
}

///|
fn TextProbe::ligature_carets(
  self : TextProbe,
  glyph : Glyph,
) -> Array[Double] raise @failure.Failure {
  let font = self.fonts[glyph.font].font
  let table = match font.gdef() {
    Ok(table) => table
    Err(_) => @failure.reject("malformed-font", "Invalid GDEF table")
  }
  guard table is Some(table) &&
    table.header().lig_caret_list_offset is Some(list) else {
    return []
  }
  ligature_values(table.data, list, glyph.id).map(value => {
    let coordinate = if value.0 == 2 {
      match font.glyph_contour_point_for_origin(glyph.id, value.1) {
        Ok(Some((x, _))) => x
        _ =>
          @failure.reject("malformed-font", "Invalid GDEF caret contour point")
      }
    } else {
      value.1
    }
    glyph.xOffset.to_double() * glyph.scale +
    coordinate.to_double() * glyph.scale
  })
}
