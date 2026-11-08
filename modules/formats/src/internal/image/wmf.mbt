///|
fn wmf_signed(bytes : Bytes, offset : Int32) -> Double raise @failure.Failure {
  (emf_uint(bytes, offset, 2) << 16 >> 16).to_double()
}

///|
// ONLYOFFICE CWmfParserBase uses the window mapping and the first free object slot.
// shortcut: Placeable WMF supports solid polygon/polyline drawings; extend other records when a real input requires them.
pub fn read_wmf(bytes : Bytes) -> @layout.Metafile raise @failure.Failure {
  guard bytes.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "WMF input exceeds budget")
  }
  guard bytes.length() >= 46 &&
    emf_uint(bytes, 0, 4) == -1698247209 &&
    emf_uint(bytes, 4, 2) == 0 &&
    emf_uint(bytes, 14, 2) > 0 &&
    emf_uint(bytes, 16, 4) == 0 &&
    [1, 2].contains(emf_uint(bytes, 22, 2)) &&
    emf_uint(bytes, 24, 2) == 9 &&
    [0x100, 0x300].contains(emf_uint(bytes, 26, 2)) &&
    emf_uint(bytes, 28, 4) == (bytes.length() - 22) / 2 &&
    bytes.length() % 2 == 0 &&
    emf_uint(bytes, 38, 2) == 0 else {
    @failure.reject("invalid-image", "Invalid placeable WMF header")
  }
  let mut checksum = 0
  for offset in 0..<10 {
    checksum = checksum ^ emf_uint(bytes, offset * 2, 2)
  }
  guard checksum == emf_uint(bytes, 20, 2) else {
    @failure.reject("invalid-image", "Invalid WMF placeable checksum")
  }
  let left = wmf_signed(bytes, 6)
  let top = wmf_signed(bytes, 8)
  let width = wmf_signed(bytes, 10) - left
  let height = wmf_signed(bytes, 12) - top
  let handles = emf_uint(bytes, 32, 2)
  let maximum = emf_uint(bytes, 34, 4)
  guard width > 0 &&
    height > 0 &&
    handles <= 256 &&
    maximum >= 3 &&
    maximum <= (bytes.length() - 40) / 2 else {
    @failure.reject(
      "limit-exceeded", "WMF bounds, objects or record size exceed budget",
    )
  }
  let objects : Map[Int32, EmfObject] = Map([])
  let commands : Array[@layout.MetafileCommand] = []
  let mut origin = (left, top)
  let mut extent = (width, height)
  let mut brush = "ffffff"
  let mut pen = ("000000", 0.0, emf_pen_style())
  let mut brush_handle = -1
  let mut pen_handle = -1
  let mut odd = true
  let mut segments = 0
  let mut count = 0
  let mut at = 40
  let mut done = false
  while at < bytes.length() {
    let words = emf_uint(bytes, at, 4)
    guard !done &&
      count < 8192 &&
      words >= 3 &&
      words <= maximum &&
      words <= (bytes.length() - at) / 2 else {
      @failure.reject("invalid-image", "Invalid WMF record bounds or count")
    }
    let record = bytes[at:at + words * 2].to_owned()
    let kind = emf_uint(record, 4, 2)
    let size = record.length()
    match kind {
      0 => {
        guard size == 6 && at + size == bytes.length() else {
          @failure.reject("invalid-image", "Invalid WMF end record")
        }
        done = true
      }
      0x20b | 0x20c => {
        guard size >= 10 else {
          @failure.reject("invalid-image", "Truncated WMF window record")
        }
        let value = (wmf_signed(record, 8), wmf_signed(record, 6))
        if kind == 0x20b {
          origin = value
        } else {
          guard value.0 != 0 && value.1 != 0 else {
            @failure.reject("invalid-image", "Zero WMF window extent")
          }
          extent = value
        }
      }
      0x2fc | 0x2fa => {
        guard size >= (if kind == 0x2fc { 14 } else { 16 }) else {
          @failure.reject("invalid-image", "Truncated WMF brush or pen")
        }
        let slot = for index in 0..<handles {
          if !objects.contains(index) {
            break index
          }
        } nobreak {
          @failure.reject("limit-exceeded", "WMF object table is full")
        }
        let style = emf_uint(record, 6, 2)
        objects[slot] = if kind == 0x2fc {
          guard [0, 1].contains(style) else {
            @failure.reject(
              "unsupported-image", "WMF brush requires solid or null paint",
            )
          }
          Brush(if style == 1 { "" } else { emf_color(emf_uint(record, 8, 4)) })
        } else {
          guard [0, 5].contains(style) else {
            @failure.reject(
              "unsupported-image", "WMF pen requires solid or null paint",
            )
          }
          Pen(
            if style == 5 {
              ""
            } else {
              emf_color(emf_uint(record, 12, 4))
            },
            wmf_signed(record, 8).abs(),
            emf_pen_style(),
          )
        }
      }
      0x12d => {
        guard size >= 8 else {
          @failure.reject("invalid-image", "Truncated WMF object selection")
        }
        let handle = emf_uint(record, 6, 2)
        let object = if handle >= 0x8000 {
          match handle & 0x7fff {
            0 => Brush("ffffff")
            1 => Brush("c0c0c0")
            2 => Brush("808080")
            3 => Brush("404040")
            4 => Brush("000000")
            5 => Brush("")
            6 => Pen("ffffff", 0, emf_pen_style())
            7 => Pen("000000", 0, emf_pen_style())
            8 => Pen("", 0, emf_pen_style())
            _ =>
              @failure.reject(
                "unsupported-image", "Unsupported WMF stock object",
              )
          }
        } else {
          objects
          .get(handle)
          .unwrap_or_error(
            @failure.Failure(
              code="invalid-image",
              message="Missing WMF object handle",
              part="",
              offset=at,
            ),
          )
        }
        match object {
          Brush(color) => {
            brush = color
            brush_handle = handle
          }
          Pen(color, width, style) => {
            pen = (color, width, style)
            pen_handle = handle
          }
          _ =>
            @failure.reject(
              "unsupported-image", "Unsupported WMF selected object",
            )
        }
      }
      0x1f0 => {
        guard size >= 8 else {
          @failure.reject("invalid-image", "Truncated WMF object deletion")
        }
        let handle = emf_uint(record, 6, 2)
        guard objects.contains(handle) &&
          handle != pen_handle &&
          handle != brush_handle else {
          @failure.reject("invalid-image", "Invalid WMF object deletion")
        }
        objects.remove(handle)
      }
      0x104 | 0x106 => {
        guard size >= 8 else {
          @failure.reject("invalid-image", "Truncated WMF paint mode")
        }
        let mode = emf_uint(record, 6, 2)
        if kind == 0x104 {
          guard mode == 13 else {
            @failure.reject(
              "unsupported-image", "WMF raster operation requires copy pen",
            )
          }
        } else {
          guard [1, 2].contains(mode) else {
            @failure.reject("invalid-image", "Invalid WMF polygon fill mode")
          }
          odd = mode == 1
        }
      }
      0x324 | 0x325 => {
        guard size >= 8 else {
          @failure.reject("invalid-image", "Truncated WMF polygon")
        }
        let points = emf_uint(record, 6, 2)
        guard points >= (if kind == 0x324 { 3 } else { 2 }) &&
          points <= 65536 - segments &&
          points <= (size - 8) / 4 else {
          @failure.reject(
            "invalid-image", "Invalid WMF polygon bounds or budget",
          )
        }
        let path : Array[@layout.PathSegment] = Array::makei(points, index => {
          let x = (wmf_signed(record, 8 + index * 4) - origin.0) *
            width /
            extent.0
          let y = (wmf_signed(record, 10 + index * 4) - origin.1) *
            height /
            extent.1
          if index == 0 {
            @layout.Move(x, y)
          } else {
            @layout.Line(x, y)
          }
        })
        if kind == 0x324 {
          path.push(@layout.Close)
        }
        commands.push(
          @layout.Vector(
            path,
            if kind == 0x324 {
              brush
            } else {
              ""
            },
            pen.0,
            if pen.1 == 0 {
              1
            } else {
              (pen.1 * width / extent.0).abs()
            },
            { ..pen.2, evenOdd: odd, },
            None,
          ),
        )
        segments += points
      }
      _ =>
        @failure.reject(
          "unsupported-image",
          "Unsupported WMF drawing record: " + kind.to_string(),
        )
    }
    count += 1
    at += size
  }
  guard done else { @failure.reject("invalid-image", "Missing WMF end record") }
  @layout.Metafile::new({ x: 0, y: 0, width, height, }, commands)
}
