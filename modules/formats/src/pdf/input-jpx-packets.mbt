///|
priv struct JpxBits {
  reader : JpxReader
  mut byte : Int32
  mut remaining : Int32
}

///|
fn JpxBits::read(self : JpxBits, count~ : Int32 = 1) -> Int32 raise {
  guard count <= 30 else {
    @failure.reject("limit-exceeded", "JPEG2000 packet integer exceeds budget")
  }
  let mut result = 0
  for _ in 0..<count {
    if self.remaining == 0 {
      self.remaining = if self.byte == 255 { 7 } else { 8 }
      self.byte = self.reader.word(count=1)
      guard self.remaining == 8 || self.byte < 128 else {
        @failure.reject("invalid-pdf", "Invalid JPEG2000 packet bit stuffing")
      }
    }
    self.remaining -= 1
    result = (result << 1) | ((self.byte >> self.remaining) & 1)
  }
  result
}

///|
fn JpxBits::finish(self : JpxBits) -> Unit raise {
  if self.byte == 255 {
    guard self.reader.word(count=1) < 128 else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 packet padding")
    }
  }
}

///|
fn jpx_tree(width : Int32, height : Int32) -> JpxTree raise {
  let widths : Array[Int32] = []
  let nodes : Array[Array[(Int32, Bool)]] = []
  let mut w = width
  let mut h = height
  while w > 0 && h > 0 {
    @pdfcore.sdk_decoded(w * h * 8)
    widths.push(w)
    nodes.push(Array::make(w * h, (0, false)))
    if w == 1 && h == 1 {
      break
    }
    w = (w + 1) / 2
    h = (h + 1) / 2
  }
  { widths, nodes, }
}

///|
fn JpxTree::decode(
  self : JpxTree,
  index : Int32,
  threshold : Int32,
  bits : JpxBits,
) -> Bool raise {
  let x = index % self.widths[0]
  let y = index / self.widths[0]
  let mut low = 0
  for level = self.nodes.length() - 1; level >= 0; level = level - 1 {
    let at = (y >> level) * self.widths[level] + (x >> level)
    let (stored, known) = self.nodes[level][at]
    let mut value = stored.max(low)
    let mut known = known
    while !known && value < threshold {
      @pdfcore.sdk_check(1)
      if bits.read() == 1 {
        known = true
      } else {
        value += 1
      }
    }
    self.nodes[level][at] = (value, known)
    low = value
  }
  self.nodes[0][index].0 < threshold
}

///|
fn jpx_band(
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  orientation : Int32,
  resolution : Int32,
  coding : JpxCoding,
) -> JpxBand raise {
  let columns = jpx_ceil(x1, coding.blockWidth) - x0 / coding.blockWidth
  let rows = jpx_ceil(y1, coding.blockHeight) - y0 / coding.blockHeight
  let count = if x0 == x1 || y0 == y1 { 0 } else { columns * rows }
  guard count <= 65536 else {
    @failure.reject(
      "limit-exceeded", "JPEG2000 code block count exceeds budget",
    )
  }
  @pdfcore.sdk_decoded(count * 96)
  let blocks : Array[JpxBlock] = Array::makei(count, index => {
    let left = ((x0 / coding.blockWidth + index % columns) * coding.blockWidth).max(
      x0,
    )
    let top = ((y0 / coding.blockHeight + index / columns) * coding.blockHeight).max(
      y0,
    )
    let right = left +
      (coding.blockWidth - left % coding.blockWidth).min(x1 - left)
    let bottom = top +
      (coding.blockHeight - top % coding.blockHeight).min(y1 - top)
    {
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
      included: false,
      zeroBits: 0,
      passes: 0,
      lengthBits: 3,
      data: [],
    }
  })
  {
    x0,
    y0,
    width: x1 - x0,
    height: y1 - y0,
    orientation,
    resolution,
    blocks,
    inclusion: jpx_tree(if count == 0 { 0 } else { columns }, rows),
    zeros: jpx_tree(if count == 0 { 0 } else { columns }, rows),
  }
}

///|
fn jpx_tile(header : JpxHeader, index : Int32) -> JpxTile raise {
  let columns = jpx_ceil(header.x1 - header.tileX, header.tileWidth)
  let rows = jpx_ceil(header.y1 - header.tileY, header.tileHeight)
  guard index < columns * rows &&
    header.coding.length() == header.components.length() &&
    header.quant.length() == header.components.length() else {
    @failure.reject("invalid-pdf", "Incomplete JPEG2000 tile header")
  }
  let left = header.tileX.to_int64() +
    (index % columns).to_int64() * header.tileWidth.to_int64()
  let top = header.tileY.to_int64() +
    (index / columns).to_int64() * header.tileHeight.to_int64()
  let x0 = left.max(header.x0.to_int64()).to_int()
  let y0 = top.max(header.y0.to_int64()).to_int()
  let x1 = (left + header.tileWidth.to_int64())
    .min(header.x1.to_int64())
    .to_int()
  let y1 = (top + header.tileHeight.to_int64())
    .min(header.y1.to_int64())
    .to_int()
  let bands = header.components.mapi((component, info) => {
    let coding = header.coding[component]
    let cx0 = jpx_ceil(x0, info.dx)
    let cy0 = jpx_ceil(y0, info.dy)
    let cx1 = jpx_ceil(x1, info.dx)
    let cy1 = jpx_ceil(y1, info.dy)
    let bands : Array[JpxBand] = []
    for resolution in 0..<=coding.levels {
      let shift = coding.levels - resolution
      let rx0 = jpx_ceil(cx0, 1 << shift)
      let ry0 = jpx_ceil(cy0, 1 << shift)
      let rx1 = jpx_ceil(cx1, 1 << shift)
      let ry1 = jpx_ceil(cy1, 1 << shift)
      guard rx0 / 32768 == (rx1 - 1) / 32768 && ry0 / 32768 == (ry1 - 1) / 32768 else {
        @failure.reject(
          "unsupported-pdf", "Multiple JPEG2000 precincts are unsupported",
        )
      }
      if resolution == 0 {
        bands.push(jpx_band(rx0, ry0, rx1, ry1, 0, 0, coding))
      } else {
        for orientation in 1..<=3 {
          let bx0 = jpx_ceil(
            cx0 - ((orientation & 1) << shift),
            1 << (shift + 1),
          )
          let by0 = jpx_ceil(
            cy0 - (orientation >> 1 << shift),
            1 << (shift + 1),
          )
          let bx1 = jpx_ceil(
            cx1 - ((orientation & 1) << shift),
            1 << (shift + 1),
          )
          let by1 = jpx_ceil(
            cy1 - (orientation >> 1 << shift),
            1 << (shift + 1),
          )
          bands.push(
            jpx_band(bx0, by0, bx1, by1, orientation, resolution, coding),
          )
        }
      }
    }
    bands
  })
  { x0, y0, x1, y1, header, bands, packet: 0, parts: 0, expectedParts: 0, }
}

///|
fn jpx_packet_passes(bits : JpxBits) -> Int32 raise {
  if bits.read() == 0 {
    return 1
  }
  if bits.read() == 0 {
    return 2
  }
  let value = bits.read(count=2)
  if value < 3 {
    return value + 3
  }
  let value = bits.read(count=5)
  if value < 31 {
    return value + 6
  }
  bits.read(count=7) + 37
}

///|
fn jpx_packet(
  tile : JpxTile,
  reader : JpxReader,
  layer : Int32,
  component : Int32,
  resolution : Int32,
) -> Unit raise {
  @pdfcore.sdk_check(1)
  if (tile.header.packetFlags & 2) != 0 {
    guard reader.word() == 0xff91 &&
      reader.word() == 4 &&
      reader.word() == tile.packet % 65536 else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 packet sequence marker")
    }
  }
  let bits : JpxBits = { reader, byte: 0, remaining: 0, }
  let lengths : Array[(JpxBlock, Int32)] = []
  if bits.read() != 0 {
    for band in tile.bands[component] {
      if band.resolution != resolution {
        continue
      }
      for index, block in band.blocks {
        let included = if block.included {
          bits.read() == 1
        } else {
          band.inclusion.decode(index, layer + 1, bits)
        }
        if !included {
          continue
        }
        if !block.included {
          guard band.zeros.decode(index, 31, bits) else {
            @failure.reject("invalid-pdf", "Invalid JPEG2000 zero bit planes")
          }
          block.zeroBits = band.zeros.nodes[0][index].0
          block.included = true
        }
        let passes = jpx_packet_passes(bits)
        block.passes += passes
        guard block.passes <= 88 else {
          @failure.reject(
            "limit-exceeded", "JPEG2000 coding passes exceed budget",
          )
        }
        while bits.read() == 1 {
          block.lengthBits += 1
          guard block.lengthBits <= 24 else {
            @failure.reject(
              "limit-exceeded", "JPEG2000 packet length exceeds budget",
            )
          }
        }
        let mut extra = 0
        let mut value = passes
        while value > 1 {
          value = value / 2
          extra += 1
        }
        let length = bits.read(count=block.lengthBits + extra)
        lengths.push((block, length))
      }
    }
  }
  bits.finish()
  if (tile.header.packetFlags & 4) != 0 {
    guard reader.word() == 0xff92 else {
      @failure.reject("invalid-pdf", "Missing JPEG2000 packet header end")
    }
  }
  for (block, length) in lengths {
    guard length <= reader.end - reader.offset else {
      @failure.reject("invalid-pdf", "JPEG2000 code block leaves its tile")
    }
    @pdfcore.sdk_decoded(length)
    @pdfcore.sdk_check(length)
    for at in reader.offset..<(reader.offset + length) {
      block.data.push(reader.bytes[at])
    }
    reader.offset += length
  }
  tile.packet += 1
}

///|
fn jpx_packets(tile : JpxTile, reader : JpxReader) -> Unit raise {
  let header = tile.header
  let levels = header.coding.fold(init=0, (n, c) => n.max(c.levels))
  let mut packet = 0
  for
    outer in 0..<(if header.progression == 0 {
      header.layers
    } else {
      levels + 1
    }) {
    for
      inner in 0..<(if header.progression == 0 {
        levels + 1
      } else {
        header.layers
      }) {
      let layer = if header.progression == 0 { outer } else { inner }
      let resolution = if header.progression == 0 { inner } else { outer }
      for component, coding in header.coding {
        if resolution > coding.levels {
          continue
        }
        if packet >= tile.packet && reader.offset < reader.end {
          jpx_packet(tile, reader, layer, component, resolution)
        }
        packet += 1
      }
    }
  }
  guard reader.offset == reader.end else {
    @failure.reject("invalid-pdf", "Unexpected JPEG2000 tile payload")
  }
}
