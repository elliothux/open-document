///|
fn jpx_decode(
  bytes : Bytes,
  expected~ : (Int32, Int32)? = None,
) -> JpxPixels raise {
  let container = jpx_container(bytes)
  let reader : JpxReader = {
    bytes: container.bytes,
    offset: 0,
    end: container.bytes.length(),
  }
  guard reader.word() == 0xff4f && reader.word() == 0xff51 else {
    @failure.reject("invalid-pdf", "Missing JPEG2000 size marker")
  }
  let header = jpx_siz(reader.section())
  guard expected is None ||
    expected == Some((header.x1 - header.x0, header.y1 - header.y0)) else {
    @failure.reject(
      "invalid-pdf", "JPEG2000 dimensions do not match the PDF image",
    )
  }
  guard (
      container.width is None || container.width == Some(header.x1 - header.x0)
    ) &&
    (
      container.height is None ||
      container.height == Some(header.y1 - header.y0)
    ) &&
    (
      container.channels is None ||
      container.channels == Some(header.components.length())
    ) &&
    (
      container.alpha is None ||
      container.alpha.unwrap() < header.components.length()
    ) else {
    @failure.reject(
      "invalid-pdf", "JPEG2000 container dimensions do not match the codestream",
    )
  }
  let tiles : Map[Int32, JpxTile] = Map([])
  let mut inTiles = false
  let mut finished = false
  let mut count = 0
  while reader.offset < reader.end {
    @pdfcore.sdk_check(1)
    count += 1
    guard count <= 16384 else {
      @failure.reject("limit-exceeded", "JPEG2000 marker count exceeds budget")
    }
    let start = reader.offset
    let marker = reader.word()
    if marker == 0xffd9 {
      finished = true
      break
    }
    if marker != 0xff90 {
      guard !inTiles else {
        @failure.reject(
          "invalid-pdf", "Unexpected JPEG2000 marker between tiles",
        )
      }
      jpx_header_marker(header, marker, reader.section())
      continue
    }
    inTiles = true
    let section = reader.section()
    guard section.end - section.offset == 8 else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 tile start")
    }
    let index = section.word()
    let length = section.word(count=4)
    let part = section.word(count=1)
    let total = section.word(count=1)
    let end = if length == 0 {
      reader.end - 2
    } else {
      guard length <= reader.end - start - 2 else {
        @failure.reject("invalid-pdf", "JPEG2000 tile leaves its stream")
      }
      start + length
    }
    guard end >= reader.offset + 2 else {
      @failure.reject("invalid-pdf", "Invalid JPEG2000 tile length")
    }
    let prior = tiles.get(index)
    let coding = match prior {
      Some(tile) => {
        guard part == tile.parts else {
          @failure.reject("invalid-pdf", "Invalid JPEG2000 tile part order")
        }
        tile.header
      }
      None => {
        guard part == 0 else {
          @failure.reject("invalid-pdf", "Missing JPEG2000 first tile part")
        }
        { ..header, coding: header.coding.copy(), quant: header.quant.copy(), }
      }
    }
    let payload : JpxReader = {
      bytes: reader.bytes,
      offset: reader.offset,
      end,
    }
    let mut headers = 0
    while true {
      let marker = payload.word()
      if marker == 0xff93 {
        break
      }
      headers += 1
      guard headers <= 256 else {
        @failure.reject("limit-exceeded", "JPEG2000 tile header exceeds budget")
      }
      guard part == 0 || marker == 0xff64 else {
        @failure.reject(
          "unsupported-pdf", "JPEG2000 coding changes between tile parts are unsupported",
        )
      }
      jpx_header_marker(coding, marker, payload.section())
    }
    let tile = match prior {
      Some(tile) => tile
      None => jpx_tile(coding, index)
    }
    if total != 0 {
      guard tile.expectedParts == 0 || tile.expectedParts == total else {
        @failure.reject("invalid-pdf", "Conflicting JPEG2000 tile part counts")
      }
      tile.expectedParts = total
    }
    tile.parts += 1
    jpx_packets(tile, payload)
    tiles[index] = tile
    reader.offset = end
  }
  let tileCount = jpx_ceil(header.x1 - header.tileX, header.tileWidth) *
    jpx_ceil(header.y1 - header.tileY, header.tileHeight)
  guard finished && reader.offset == reader.end && tiles.length() == tileCount else {
    @failure.reject("invalid-pdf", "Incomplete JPEG2000 codestream")
  }
  let width = header.x1 - header.x0
  let height = header.y1 - header.y0
  let channels = header.components.length()
  @pdfcore.sdk_decoded(width * height * channels)
  let samples : Array[Byte] = Array::make(width * height * channels, 0)
  for index in 0..<tileCount {
    guard tiles.get(index) is Some(tile) else {
      @failure.reject("invalid-pdf", "Missing JPEG2000 tile")
    }
    let expected = tile.header.layers *
      tile.header.coding.fold(init=0, (n, c) => n + c.levels + 1)
    guard tile.packet == expected &&
      (tile.expectedParts == 0 || tile.parts == tile.expectedParts) else {
      @failure.reject("invalid-pdf", "Incomplete JPEG2000 tile packets")
    }
    let planes = Array::makei(channels, i => jpx_component_values(tile, i))
    if tile.header.mct {
      guard channels >= 3 else {
        @failure.reject(
          "invalid-pdf", "JPEG2000 component transform requires three components",
        )
      }
      let reversible = tile.header.coding[0].reversible
      for i in 0..<3 {
        guard tile.header.components[i].dx == 1 &&
          tile.header.components[i].dy == 1 else {
          @failure.reject(
            "unsupported-pdf", "Unsupported JPEG2000 component transform geometry",
          )
        }
        guard tile.header.coding[i].reversible == reversible else {
          @failure.reject(
            "invalid-pdf", "JPEG2000 component transforms do not match",
          )
        }
      }
      for i in 0..<planes[0].length() {
        let y = planes[0][i]
        let cb = planes[1][i]
        let cr = planes[2][i]
        if reversible {
          let green = y - ((cb + cr) / 4.0).floor()
          planes[0][i] = green + cr
          planes[1][i] = green
          planes[2][i] = green + cb
        } else {
          planes[0][i] = y + 1.402 * cr
          planes[1][i] = y - 0.34413 * cb - 0.71414 * cr
          planes[2][i] = y + 1.772 * cb
        }
      }
    }
    @pdfcore.sdk_check((tile.x1 - tile.x0) * (tile.y1 - tile.y0) * channels)
    for component, info in header.components {
      let left = jpx_ceil(tile.x0, info.dx)
      let top = jpx_ceil(tile.y0, info.dy)
      let right = jpx_ceil(tile.x1, info.dx)
      let bottom = jpx_ceil(tile.y1, info.dy)
      guard right > left && bottom > top else {
        @failure.reject(
          "unsupported-pdf", "Empty JPEG2000 tile components are unsupported",
        )
      }
      let maximum = (1 << info.precision) - 1
      let minimum = if info.signed { -(1 << (info.precision - 1)) } else { 0 }
      for y in tile.y0..<tile.y1 {
        for x in tile.x0..<tile.x1 {
          let sx = (x / info.dx).max(left).min(right - 1) - left
          let sy = (y / info.dy).max(top).min(bottom - 1) - top
          let value = planes[component][sy * (right - left) + sx] +
            (if info.signed {
              0.0
            } else {
              (1 << (info.precision - 1)).to_double()
            })
          let sample = value
            .round()
            .to_int()
            .max(minimum)
            .min(maximum + minimum) -
            minimum
          samples[((y - header.y0) * width + x - header.x0) * channels +
          component] = (sample.to_double() * 255.0 / maximum.to_double())
            .round()
            .to_int()
            .to_byte()
        }
      }
    }
  }
  {
    width,
    height,
    components: header.components,
    samples: Bytes::from_array(samples),
    color: container.color,
    alpha: container.alpha,
    associated: container.associated,
  }
}
