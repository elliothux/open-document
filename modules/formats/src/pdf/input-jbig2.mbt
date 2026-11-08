///|
fn jbig2_word(
  bytes : Bytes,
  offset : Int32,
  size~ : Int32 = 4,
) -> Int64 raise @failure.Failure {
  guard offset >= 0 && offset <= bytes.length() - size else {
    @failure.reject("invalid-pdf", "Truncated JBIG2 segment")
  }
  let mut value = 0L
  for index in offset..<(offset + size) {
    value = value * 256 + bytes[index].to_int64()
  }
  value
}

///|
fn jbig2_samples(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  width : Int32,
  height : Int32,
) -> Bytes raise {
  let parameters = match get(document, object, "DecodeParms") {
    PdfArray([value]) => resolve(document, value)
    value => value
  }
  guard parameters == @syntax.PdfNull ||
    (parameters is PdfDictionary(entries) && entries.is_empty()) else {
    @failure.reject(
      "unsupported-pdf", "JBIG2 global dictionaries are unsupported",
    )
  }
  let bytes = object.deep_copy().stream_bytes()
  let file = bytes.length() >= 8 && bytes[:8] == b"\x97JB2\r\n\x1a\n"
  let mut offset = 0
  if file {
    let flags = jbig2_word(bytes, 8, size=1).to_int()
    guard (flags & 252) == 0 && (flags & 1) == 1 else {
      @failure.reject("unsupported-pdf", "JBIG2 requires sequential segments")
    }
    offset = if (flags & 2) == 0 {
      guard jbig2_word(bytes, 9) == 1 else {
        @failure.reject("unsupported-pdf", "JBIG2 requires one image page")
      }
      13
    } else {
      9
    }
  }
  let stride = (width + 7) / 8
  @pdfcore.sdk_decoded(stride * height)
  let output : Array[Byte] = Array::make(stride * height, 0)
  let mut page : Int64? = None
  let mut previous = -1L
  let mut count = 0
  let mut ended = false
  let mut eof = false
  let mut default_operation = 0
  let mut override_operation = false
  while offset < bytes.length() {
    @pdfcore.sdk_check(1)
    count += 1
    guard count <= 256 else {
      @failure.reject("limit-exceeded", "JBIG2 segment count exceeds budget")
    }
    let number = jbig2_word(bytes, offset)
    let flags = jbig2_word(bytes, offset + 4, size=1).to_int()
    let references = jbig2_word(bytes, offset + 5, size=1).to_int() >> 5
    guard references != 5 && references != 6 else {
      @failure.reject("invalid-pdf", "Invalid JBIG2 segment reference count")
    }
    guard references == 0 else {
      @failure.reject(
        "unsupported-pdf", "JBIG2 referenced segments are unsupported",
      )
    }
    guard number > previous && !eof else {
      @failure.reject("invalid-pdf", "Invalid JBIG2 segment order")
    }
    previous = number
    let page_bytes = if (flags & 64) == 0 { 1 } else { 4 }
    let association = jbig2_word(bytes, offset + 6, size=page_bytes)
    let length = jbig2_word(bytes, offset + 6 + page_bytes)
    let start = offset + 10 + page_bytes
    guard length <= (bytes.length() - start).to_int64() else {
      @failure.reject("invalid-pdf", "JBIG2 segment leaves its stream")
    }
    let size = length.to_int()
    let kind = flags & 63
    if kind == 48 {
      guard page is None && association != 0 && size == 19 else {
        @failure.reject("invalid-pdf", "Invalid JBIG2 page information")
      }
      guard jbig2_word(bytes, start) == width.to_int64() &&
        jbig2_word(bytes, start + 4) == height.to_int64() else {
        @failure.reject(
          "invalid-pdf", "JBIG2 geometry does not match the image",
        )
      }
      let page_flags = bytes[start + 16].to_int()
      guard (page_flags & 128) == 0 &&
        (jbig2_word(bytes, start + 17, size=2) & 32768L) == 0 else {
        @failure.reject(
          "unsupported-pdf", "JBIG2 striped pages are unsupported",
        )
      }
      page = Some(association)
      default_operation = (page_flags >> 3) & 3
      override_operation = (page_flags & 64) != 0
      if (page_flags & 4) != 0 {
        output.fill(255)
      }
    } else if kind == 38 || kind == 39 {
      guard page == Some(association) && !ended && size >= 18 else {
        @failure.reject("invalid-pdf", "Invalid JBIG2 generic region")
      }
      let region_width = jbig2_word(bytes, start)
      let region_height = jbig2_word(bytes, start + 4)
      let x = jbig2_word(bytes, start + 8)
      let y = jbig2_word(bytes, start + 12)
      guard region_width > 0 &&
        region_height > 0 &&
        region_width <= 4096 &&
        region_height <= 4096 &&
        region_width * region_height <= 4194304 &&
        x <= 2147483647L &&
        y <= 2147483647L else {
        @failure.reject(
          "limit-exceeded", "JBIG2 region geometry exceeds budget",
        )
      }
      let operation = bytes[start + 16].to_int()
      guard operation <= 4 else {
        @failure.reject("invalid-pdf", "Invalid JBIG2 region combination")
      }
      let operation = if override_operation {
        operation
      } else {
        default_operation
      }
      let coding = bytes[start + 17].to_int()
      let rw = region_width.to_int()
      let rh = region_height.to_int()
      let fax = @syntax.pdf_stream(
        dict([
          ("Filter", tag("CCITTFaxDecode")),
          ("Length", @syntax.PdfInteger(size - 18)),
          (
            "DecodeParms",
            dict([
              ("K", @syntax.PdfInteger(-1)),
              ("Columns", @syntax.PdfInteger(rw)),
              ("Rows", @syntax.PdfInteger(rh)),
              ("BlackIs1", @syntax.PdfBoolean(true)),
            ]),
          ),
        ]),
        @syntax.StreamGot(bytes[start + 18:start + size].to_owned()),
      )
      let region = if (coding & 1) == 1 {
        guard (coding & 248) == 0 else {
          @failure.reject("invalid-pdf", "Invalid JBIG2 MMR flags")
        }
        image_stream_bytes(document, fax, rw, rh, 1, 1)
      } else {
        jbig2_arithmetic_region(
          bytes[start + 18:start + size].to_owned(),
          rw,
          rh,
          coding,
        )
      }
      let visible_width = (width.to_int64() - x)
        .max(0)
        .min(region_width)
        .to_int()
      let visible_height = (height.to_int64() - y)
        .max(0)
        .min(region_height)
        .to_int()
      @pdfcore.sdk_check(visible_width * visible_height)
      for row in 0..<visible_height {
        for column in 0..<visible_width {
          let value = (
              region[row * ((rw + 7) / 8) + column / 8].to_int() >>
              (7 - column % 8)
            ) &
            1
          let column = column + x.to_int()
          let target = (row + y.to_int()) * stride + column / 8
          let shift = 7 - column % 8
          let old = (output[target].to_int() >> shift) & 1
          let result = match operation {
            0 => old | value
            1 => old & value
            2 => old ^ value
            3 => 1 ^ old ^ value
            _ => value
          }
          output[target] = ((output[target].to_int() & (255 ^ (1 << shift))) |
          (result << shift)).to_byte()
        }
      }
    } else if kind == 49 {
      guard page == Some(association) && !ended && size == 0 else {
        @failure.reject("invalid-pdf", "Invalid JBIG2 end of page")
      }
      ended = true
    } else if kind == 51 {
      guard page is Some(_) && size == 0 else {
        @failure.reject("invalid-pdf", "Invalid JBIG2 end of file")
      }
      eof = true
    } else {
      @failure.reject("unsupported-pdf", "Unsupported JBIG2 segment type")
    }
    offset = start + size
  }
  guard page is Some(_) && (!file || eof) else {
    @failure.reject("invalid-pdf", "Incomplete JBIG2 image")
  }
  // JBIG2 stores black as one; PDF's default grayscale Decode stores white as one.
  Bytes::makei(output.length(), index => output[index] ^ 255)
}
