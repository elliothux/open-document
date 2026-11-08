///|
fn jpx_siz(reader : JpxReader) -> JpxHeader raise {
  let _ = reader.word()
  let x1 = reader.word(count=4)
  let y1 = reader.word(count=4)
  let x0 = reader.word(count=4)
  let y0 = reader.word(count=4)
  let tileWidth = reader.word(count=4)
  let tileHeight = reader.word(count=4)
  let tileX = reader.word(count=4)
  let tileY = reader.word(count=4)
  let channels = reader.word()
  guard x1 > x0 &&
    y1 > y0 &&
    x1 - x0 <= 4096 &&
    y1 - y0 <= 4096 &&
    (x1 - x0).to_int64() * (y1 - y0).to_int64() <= 4194304 &&
    tileWidth > 0 &&
    tileHeight > 0 &&
    tileX <= x0 &&
    tileY <= y0 &&
    x0 - tileX < tileWidth &&
    y0 - tileY < tileHeight &&
    channels > 0 &&
    channels <= 5 else {
    @failure.reject("limit-exceeded", "JPEG2000 geometry exceeds budget")
  }
  let tiles = jpx_ceil(x1 - tileX, tileWidth).to_int64() *
    jpx_ceil(y1 - tileY, tileHeight).to_int64()
  guard tiles <= 4096 && reader.end - reader.offset == channels * 3 else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 size marker")
  }
  let components : Array[JpxComponent] = Array::makei(channels, _ => {
    let precision = reader.word(count=1)
    let dx = reader.word(count=1)
    let dy = reader.word(count=1)
    guard (precision & 127) < 16 && dx > 0 && dy > 0 else {
      @failure.reject(
        "unsupported-pdf", "Unsupported JPEG2000 component precision",
      )
    }
    {
      precision: (precision & 127) + 1,
      signed: (precision & 128) != 0,
      dx,
      dy,
    }
  })
  {
    x0,
    y0,
    x1,
    y1,
    tileX,
    tileY,
    tileWidth,
    tileHeight,
    components,
    coding: [],
    quant: [],
    layers: 0,
    progression: 0,
    mct: false,
    packetFlags: 0,
  }
}

///|
fn jpx_coding(reader : JpxReader, flags : Int32) -> JpxCoding raise {
  let levels = reader.word(count=1)
  let width = reader.word(count=1) + 2
  let height = reader.word(count=1) + 2
  let style = reader.word(count=1)
  let transform = reader.word(count=1)
  guard levels <= 16 &&
    width <= 10 &&
    height <= 10 &&
    width + height <= 12 &&
    transform <= 1 &&
    (flags & 249) == 0 &&
    (style & 213) == 0 else {
    @failure.reject("unsupported-pdf", "Unsupported JPEG2000 coding style")
  }
  guard reader.offset == reader.end else {
    @failure.reject("invalid-pdf", "Unexpected JPEG2000 coding parameters")
  }
  {
    levels,
    blockWidth: 1 << width,
    blockHeight: 1 << height,
    style,
    reversible: transform == 1,
  }
}

///|
fn jpx_quant(reader : JpxReader) -> JpxQuant raise {
  let flags = reader.word(count=1)
  let style = flags & 31
  guard style <= 2 else {
    @failure.reject("unsupported-pdf", "Unsupported JPEG2000 quantization")
  }
  let steps : Array[(Int32, Int32)] = []
  while reader.offset < reader.end {
    @pdfcore.sdk_check(1)
    guard steps.length() < 49 else {
      @failure.reject("limit-exceeded", "JPEG2000 quantization exceeds budget")
    }
    let value = reader.word(count=if style == 0 { 1 } else { 2 })
    if style == 0 {
      guard (value & 7) == 0 else {
        @failure.reject("invalid-pdf", "Invalid JPEG2000 quantization exponent")
      }
      steps.push((value >> 3, 0))
    } else {
      steps.push((value >> 11, value & 2047))
    }
  }
  guard !steps.is_empty() && (style != 1 || steps.length() == 1) else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 quantization table")
  }
  { style, guardBits: flags >> 5, steps, }
}

///|
fn jpx_header_marker(
  header : JpxHeader,
  marker : Int32,
  reader : JpxReader,
) -> Unit raise {
  if marker == 0xff52 {
    let flags = reader.word(count=1)
    let progression = reader.word(count=1)
    let layers = reader.word()
    let mct = reader.word(count=1)
    guard progression <= 1 && layers > 0 && layers <= 256 && mct <= 1 else {
      @failure.reject(
        "unsupported-pdf", "Unsupported JPEG2000 packet progression",
      )
    }
    header.layers = layers
    header.progression = progression
    header.mct = mct == 1
    header.packetFlags = flags
    let coding = jpx_coding(reader, flags)
    header.coding.clear()
    for _ in header.components {
      header.coding.push(coding)
    }
  } else if marker == 0xff53 {
    let index = reader.word(count=1)
    guard index < header.components.length() &&
      header.coding.length() == header.components.length() else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 coding component")
    }
    let flags = reader.word(count=1)
    header.coding[index] = jpx_coding(reader, flags)
  } else if marker == 0xff5c {
    let quant = jpx_quant(reader)
    header.quant.clear()
    for _ in header.components {
      header.quant.push(quant)
    }
  } else if marker == 0xff5d {
    let index = reader.word(count=1)
    guard index < header.quant.length() else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 quantization component")
    }
    header.quant[index] = jpx_quant(reader)
  } else {
    guard [0xff55, 0xff57, 0xff58, 0xff64].contains(marker) else {
      @failure.reject("unsupported-pdf", "Unsupported JPEG2000 marker")
    }
  }
}

///|
fn JpxQuant::step(
  self : JpxQuant,
  index : Int32,
  levels : Int32,
) -> (Int32, Int32) raise {
  if self.style == 1 {
    let (exponent, mantissa) = self.steps[0]
    let exponent = exponent - (if index == 0 { 0 } else { (index - 1) / 3 })
    guard exponent >= 0 else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 derived quantization")
    }
    return (exponent, mantissa)
  }
  guard self.steps.length() == levels * 3 + 1 && index < self.steps.length() else {
    @failure.reject("invalid-pdf", "Incomplete JPEG2000 quantization table")
  }
  self.steps[index]
}
