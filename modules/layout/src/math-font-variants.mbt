///|
fn math_u16(data : BytesView, offset : Int32) -> Int32 raise @failure.Failure {
  guard offset >= 0 && offset <= data.length() - 2 else {
    @failure.reject("malformed-font", "Truncated mathematical font table")
  }
  data[offset].to_int() * 256 + data[offset + 1].to_int()
}

///|
fn math_coverage(
  data : BytesView,
  offset : Int32,
  glyph : Int32,
) -> Int32? raise @failure.Failure {
  let format = math_u16(data, offset)
  let count = math_u16(data, offset + 2)
  guard format == 1 || format == 2 else {
    @failure.reject("malformed-font", "Unknown mathematical glyph coverage")
  }
  let stride = if format == 1 { 2 } else { 6 }
  ignore(math_u16(data, offset + 2 + count * stride))
  let mut low = 0
  let mut high = count
  while low < high {
    let middle = low + (high - low) / 2
    let record = offset + 4 + middle * stride
    let start = math_u16(data, record)
    let end = if format == 1 { start } else { math_u16(data, record + 2) }
    if glyph < start {
      high = middle
    } else if glyph > end {
      low = middle + 1
    } else {
      return Some(
        if format == 1 {
          middle
        } else {
          math_u16(data, record + 4) + glyph - start
        },
      )
    }
  }
  None
}

///|
priv struct MathGlyphPart {
  glyph : UInt32
  start : Double
  end : Double
  advance : Double
  extender : Bool
}

///|
fn math_assembly(
  data : BytesView,
  offset : Int32,
  minimum : Double,
  target : Double,
) -> Array[(UInt32, Double)] raise @failure.Failure {
  let count = math_u16(data, offset + 4)
  guard count > 0 && count <= 64 else {
    @failure.reject("limit-exceeded", "Mathematical assembly exceeds 64 parts")
  }
  let parts : Array[MathGlyphPart] = []
  for i in 0..<count {
    let record = offset + 6 + i * 10
    let start = math_u16(data, record + 2).to_double()
    let end = math_u16(data, record + 4).to_double()
    let advance = math_u16(data, record + 6).to_double()
    let flags = math_u16(data, record + 8)
    guard advance > 0 && start <= advance && end <= advance && flags <= 1 else {
      @failure.reject("malformed-font", "Invalid mathematical assembly part")
    }
    parts.push({
      glyph: math_u16(data, record).reinterpret_as_uint(),
      start,
      end,
      advance,
      extender: flags == 1,
    })
  }
  // OpenType MATH repeats every extender equally and distributes connector growth.
  for repeats in 0..<=256 {
    let expanded : Array[MathGlyphPart] = []
    for part in parts {
      let copies = if part.extender { repeats } else { 1 }
      guard expanded.length() + copies <= 256 else {
        @failure.reject(
          "limit-exceeded", "Mathematical assembly exceeds 256 glyphs",
        )
      }
      for _ in 0..<copies {
        expanded.push(part)
      }
    }
    if expanded.is_empty() {
      continue
    }
    let overlaps : Array[Double] = []
    for i in 1..<expanded.length() {
      let overlap = expanded[i - 1].end.min(expanded[i].start)
      guard overlap >= minimum &&
        overlap <= expanded[i - 1].advance &&
        overlap <= expanded[i].advance else {
        @failure.reject(
          "malformed-font", "Invalid mathematical assembly connector",
        )
      }
      overlaps.push(overlap)
    }
    let full = expanded.fold(init=0.0, (sum, part) => sum + part.advance)
    let smallest = full - overlaps.fold(init=0.0, (sum, value) => sum + value)
    let largest = full - overlaps.length().to_double() * minimum
    if largest < target {
      continue
    }
    let needed = target.max(smallest) - smallest
    let mut low = 0.0
    let mut high = overlaps.fold(init=0.0, (value, overlap) => {
      value.max(overlap - minimum)
    })
    for _ in 0..<32 {
      let middle = (low + high) / 2
      let growth = overlaps.fold(init=0.0, (sum, overlap) => {
        sum + middle.min(overlap - minimum)
      })
      if growth < needed {
        low = middle
      } else {
        high = middle
      }
    }
    let positions : Array[(UInt32, Double)] = []
    let mut position = 0.0
    for i, part in expanded {
      positions.push((part.glyph, position))
      if i < overlaps.length() {
        position += part.advance - overlaps[i] + high.min(overlaps[i] - minimum)
      }
    }
    return positions
  }
  @failure.reject(
    "limit-exceeded", "Mathematical assembly cannot reach required height",
  )
}

///|
fn TextProbe::math_variant(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
  target : Double,
) -> Array[(UInt32, Double)] raise @failure.Failure {
  let font = self.fonts[index].font
  guard font.get_face().reference_table(@common.Tag::from_string("MATH"))
    is Ok(blob) else {
    @failure.reject(
      "unsupported-font", "Growing delimiters require a MATH font table",
    )
  }
  let data = blob.as_view()
  guard math_u16(data, 0) == 1 else {
    @failure.reject("malformed-font", "Unknown mathematical font version")
  }
  let variants = math_u16(data, 8)
  guard variants != 0 else {
    @failure.reject("unsupported-font", "Font has no mathematical variants")
  }
  let coverage = math_u16(data, variants + 2)
  guard coverage != 0 &&
    math_coverage(data, variants + coverage, glyph.reinterpret_as_int())
    is Some(item) else {
    @failure.reject(
      "unsupported-font", "Font has no growing variant for this delimiter",
    )
  }
  guard item < math_u16(data, variants + 6) else {
    @failure.reject(
      "malformed-font", "Mathematical coverage exceeds construction count",
    )
  }
  let relative = math_u16(data, variants + 10 + item * 2)
  guard relative != 0 else {
    @failure.reject("malformed-font", "Missing mathematical glyph construction")
  }
  let construction = variants + relative
  let count = math_u16(data, construction + 2)
  guard count <= 128 else {
    @failure.reject("limit-exceeded", "Mathematical glyph exceeds 128 variants")
  }
  for i in 0..<count {
    let record = construction + 4 + i * 4
    if math_u16(data, record + 2).to_double() >= target {
      return [(math_u16(data, record).reinterpret_as_uint(), 0)]
    }
  }
  let assembly = math_u16(data, construction)
  guard assembly != 0 else {
    @failure.reject(
      "unsupported-font", "Font delimiter cannot reach required height",
    )
  }
  math_assembly(
    data,
    construction + assembly,
    math_u16(data, variants).to_double(),
    target,
  )
}
