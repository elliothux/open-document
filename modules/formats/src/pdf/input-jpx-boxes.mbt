///|
fn jpx_container(bytes : Bytes) -> JpxContainer raise {
  if bytes.length() >= 2 && bytes[:2] == b"\xff\x4f" {
    return {
      bytes,
      width: None,
      height: None,
      channels: None,
      color: None,
      alpha: None,
      associated: false,
    }
  }
  guard bytes.length() >= 12 && bytes[:12] == b"\x00\x00\x00\x0cjP  \r\n\x87\n" else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 signature")
  }
  let outer : JpxReader = { bytes, offset: 12, end: bytes.length(), }
  let mut codestream : Bytes? = None
  let mut dimensions : (Int32, Int32, Int32)? = None
  let mut color : Int32? = None
  let mut alpha : Int32? = None
  let mut associated = false
  let mut count = 0
  while outer.offset < outer.end {
    @pdfcore.sdk_check(1)
    count += 1
    guard count <= 256 else {
      @failure.reject("limit-exceeded", "JPEG2000 box count exceeds budget")
    }
    let start = outer.offset
    let size = outer.word(count=4)
    let kind = outer.word(count=4)
    let size = if size == 1 {
      guard outer.word(count=4) == 0 else {
        @failure.reject("limit-exceeded", "JPEG2000 box exceeds budget")
      }
      outer.word(count=4)
    } else if size == 0 {
      outer.end - start
    } else {
      size
    }
    guard size >= outer.offset - start && size <= outer.end - start else {
      @failure.reject("invalid-pdf", "JPEG2000 box leaves its stream")
    }
    let section : JpxReader = {
      bytes,
      offset: outer.offset,
      end: start + size,
    }
    outer.offset = start + size
    if kind == 0x6a703263 {
      guard codestream is None else {
        @failure.reject(
          "unsupported-pdf", "Multiple JPEG2000 codestreams are unsupported",
        )
      }
      @pdfcore.sdk_decoded(section.end - section.offset)
      codestream = Some(bytes[section.offset:section.end].to_owned())
    } else if kind == 0x6a703268 {
      while section.offset < section.end {
        @pdfcore.sdk_check(1)
        count += 1
        guard count <= 256 else {
          @failure.reject("limit-exceeded", "JPEG2000 box count exceeds budget")
        }
        let start = section.offset
        let size = section.word(count=4)
        let kind = section.word(count=4)
        guard size >= 8 && size <= section.end - start else {
          @failure.reject("invalid-pdf", "Invalid JPEG2000 header box")
        }
        let entry : JpxReader = {
          bytes,
          offset: section.offset,
          end: start + size,
        }
        section.offset = start + size
        if kind == 0x69686472 {
          guard dimensions is None && size == 22 else {
            @failure.reject("invalid-pdf", "Invalid JPEG2000 image header")
          }
          let height = entry.word(count=4)
          let width = entry.word(count=4)
          let channels = entry.word()
          let _ = entry.word(count=1)
          guard entry.word(count=1) == 7 else {
            @failure.reject(
              "unsupported-pdf", "Unsupported JPEG2000 compression",
            )
          }
          dimensions = Some((width, height, channels))
        } else if kind == 0x636f6c72 {
          let mode = entry.word(count=1)
          let _ = entry.word()
          guard mode == 1 && entry.end - entry.offset == 4 else {
            @failure.reject(
              "unsupported-pdf", "Unsupported JPEG2000 embedded color profile",
            )
          }
          let value = entry.word(count=4)
          guard [16, 17, 18].contains(value) else {
            @failure.reject(
              "unsupported-pdf", "Unsupported JPEG2000 embedded color space",
            )
          }
          guard color is None || color == Some(value) else {
            @failure.reject(
              "unsupported-pdf", "Conflicting JPEG2000 color specifications",
            )
          }
          color = Some(value)
        } else if kind == 0x63646566 {
          let length = entry.word()
          guard length <= 16 && entry.end - entry.offset == length * 6 else {
            @failure.reject(
              "invalid-pdf", "Invalid JPEG2000 channel definition",
            )
          }
          let seen : Map[Int32, Bool] = Map([])
          for _ in 0..<length {
            let index = entry.word()
            let kind = entry.word()
            let association = entry.word()
            guard !seen.contains(index) else {
              @failure.reject(
                "invalid-pdf", "Duplicate JPEG2000 channel definition",
              )
            }
            seen[index] = true
            if kind == 1 || kind == 2 {
              guard alpha is None && association == 0 else {
                @failure.reject(
                  "unsupported-pdf", "Unsupported JPEG2000 opacity channels",
                )
              }
              alpha = Some(index)
              associated = kind == 2
            } else {
              guard kind == 0 && association == index + 1 else {
                @failure.reject(
                  "unsupported-pdf", "Unsupported JPEG2000 channel mapping",
                )
              }
            }
          }
        } else {
          guard kind == 0x62706363 || kind == 0x72657320 else {
            @failure.reject(
              "unsupported-pdf", "Unsupported JPEG2000 header box",
            )
          }
        }
      }
    } else {
      guard [0x66747970, 0x66726565, 0x75756964, 0x786d6c20].contains(kind) else {
        @failure.reject("unsupported-pdf", "Unsupported JPEG2000 container box")
      }
    }
  }
  guard codestream is Some(bytes) &&
    dimensions is Some((width, height, channels)) else {
    @failure.reject("invalid-pdf", "Incomplete JPEG2000 container")
  }
  {
    bytes,
    width: Some(width),
    height: Some(height),
    channels: Some(channels),
    color,
    alpha,
    associated,
  }
}
