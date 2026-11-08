///|
priv enum EmfObject {
  Font(String, Double)
  Brush(String)
  Pen(String, Double, @layout.PathStyle)
}

///|
priv struct EmfDC {
  world : @layout.Matrix
  clip : @layout.Border?
  font : (String, Double)?
  brush : String
  pen : (String, Double, @layout.PathStyle)
  transparent : Bool
  color : String
  baseline : Bool
  odd : Bool
}

///|
priv struct EmfReader {
  handles : Int32
  objects : Map[Int32, EmfObject]
  commands : Array[@layout.MetafileCommand]
  stack : Array[EmfDC]
  mut dc : EmfDC
  mut path : Array[@layout.PathSegment]
  mut path_open : Bool
  mut path_ready : Bool
  mut segments : Int32
  mut plus_started : Bool
  mut plus_done : Bool
  mut plus_records : Int32
}

///|
fn emf_pen_style() -> @layout.PathStyle {
  {
    evenOdd: false,
    fillAlpha: 1,
    strokeAlpha: 1,
    dash: [],
    cap: 1,
    join: 1,
    miter: 10,
  }
}

///|
fn EmfReader::new(handles : Int32) -> EmfReader {
  {
    handles,
    objects: Map([]),
    commands: [],
    stack: [],
    dc: {
      world: @layout.Matrix::identity(),
      clip: None,
      font: None,
      brush: "ffffff",
      pen: ("000000", 0, emf_pen_style()),
      transparent: false,
      color: "000000",
      baseline: false,
      odd: true,
    },
    path: [],
    path_open: false,
    path_ready: false,
    segments: 0,
    plus_started: false,
    plus_done: false,
    plus_records: 0,
  }
}

///|
fn EmfReader::object(
  self : EmfReader,
  index : Int32,
  object : EmfObject,
) -> Unit raise @failure.Failure {
  guard index > 0 && index < self.handles && !self.objects.contains(index) else {
    @failure.reject("invalid-image", "Invalid EMF object handle")
  }
  self.objects[index] = object
}

///|
fn EmfReader::comment(
  self : EmfReader,
  record : Bytes,
) -> Unit raise @failure.Failure {
  let length = emf_uint(record, 8, 4)
  guard length >= 0 && length <= record.length() - 12 else {
    @failure.reject("invalid-image", "Invalid EMF comment bounds")
  }
  if length < 4 || emf_uint(record, 12, 4) != 0x2b464d45 {
    return
  }
  // MS-EMFPLUS 1.3.1: Dual records contain a complete traditional EMF drawing.
  let mut at = 16
  guard length >= 16 else {
    @failure.reject("invalid-image", "Truncated EMF+ header")
  }
  while at < length + 12 {
    let kind = emf_uint(record, at, 2)
    let flags = emf_uint(record, at + 2, 2)
    let size = emf_uint(record, at + 4, 4)
    let data = emf_uint(record, at + 8, 4)
    guard !self.plus_done &&
      size >= 12 &&
      size % 4 == 0 &&
      size <= length + 12 - at &&
      data >= 0 &&
      data <= size - 12 &&
      self.plus_records < 8192 else {
      @failure.reject("invalid-image", "Invalid EMF+ record bounds")
    }
    if !self.plus_started {
      guard kind == 0x4001 && flags == 1 && size == 28 && data == 16 else {
        @failure.reject(
          "unsupported-image", "EMF+ Only requires native playback",
        )
      }
      self.plus_started = true
    } else if kind == 0x4001 {
      @failure.reject("invalid-image", "Duplicate EMF+ header")
    }
    if kind == 0x4002 {
      guard size == 12 && data == 0 && flags == 0 else {
        @failure.reject("invalid-image", "Invalid EMF+ end record")
      }
      self.plus_done = true
    }
    at += size
    self.plus_records += 1
  }
}

///|
fn EmfReader::font_record(
  self : EmfReader,
  record : Bytes,
) -> Unit raise @failure.Failure {
  let height = emf_uint(record, 12, 4)
  guard record.length() == 368 &&
    height < 0 &&
    height >= -1024 &&
    emf_uint(record, 16, 4) == 0 &&
    emf_uint(record, 20, 4) == 0 &&
    emf_uint(record, 24, 4) == 0 &&
    [0, 1].contains(emf_uint(record, 35, 1)) &&
    emf_uint(record, 33, 1) == 0 &&
    emf_uint(record, 34, 1) == 0 else {
    @failure.reject(
      "unsupported-image", "EMF requires an upright scalable Unicode font",
    )
  }
  let name = emf_string(record, 40, 32).split("\u0000").to_array()[0].to_owned()
  let weight = emf_uint(record, 28, 4)
  guard weight >= 0 && weight <= 1000 else {
    @failure.reject("invalid-image", "Invalid EMF font weight")
  }
  let key = name +
    (if weight >= 700 { "|bold" } else { "" }) +
    (if emf_uint(record, 32, 1) != 0 { "|italic" } else { "" })
  self.object(emf_uint(record, 8, 4), Font(key, -height.to_double()))
}

///|
fn EmfReader::label(
  self : EmfReader,
  record : Bytes,
) -> Unit raise @failure.Failure {
  guard self.dc.transparent &&
    self.dc.font is Some((key, font_size)) &&
    record.length() >= 76 &&
    [1, 2].contains(emf_uint(record, 24, 4)) else {
    @failure.reject(
      "unsupported-image", "EMF text requires a selected horizontal font",
    )
  }
  let units = emf_uint(record, 44, 4)
  let offset = emf_uint(record, 48, 4)
  let flags = emf_uint(record, 52, 4)
  let dx = emf_uint(record, 72, 4)
  guard [0, 4].contains(flags) &&
    offset >= 76 &&
    dx >= 76 &&
    units > 0 &&
    units <= 32767 &&
    units <= (record.length() - dx) / 4 else {
    @failure.reject(
      "unsupported-image", "EMF text requires Unicode text and horizontal advances",
    )
  }
  let text = emf_string(record, offset, units)
  guard (dx >= offset + units * 2 || offset >= dx + units * 4) &&
    text.iter().all(c => c.to_int() >= 32) else {
    @failure.reject(
      "unsupported-image", "EMF text requires disjoint text and advance data without controls",
    )
  }
  let world = self.dc.world
  let (x, y) = world.point(
    emf_uint(record, 36, 4).to_double(),
    emf_uint(record, 40, 4).to_double() -
    (if self.dc.baseline { font_size } else { 0 }),
  )
  let clip = if flags == 4 {
    Some(self.rect(emf_rect(record, 56)))
  } else {
    None
  }
  self.commands.push(
    @layout.Label({
      text,
      font: key,
      size: font_size * world.a,
      color: self.dc.color,
      x,
      y,
      advances: Array::makei(units, i => {
        emf_uint(record, dx + i * 4, 4).to_double() * world.a
      }),
      clip: match (self.dc.clip, clip) {
        (None, clip) | (clip, None) => clip
        (Some(a), Some(b)) =>
          Some({
            x: a.x.max(b.x),
            y: a.y.max(b.y),
            width: ((a.x + a.width).min(b.x + b.width) - a.x.max(b.x)).max(0),
            height: ((a.y + a.height).min(b.y + b.height) - a.y.max(b.y)).max(0),
          })
      },
    }),
  )
}

///|
fn EmfReader::state_record(
  self : EmfReader,
  kind : Int32,
  record : Bytes,
) -> Bool raise @failure.Failure {
  let size = record.length()
  match kind {
    10 | 12 => {
      guard size == 16 &&
        emf_uint(record, 8, 4) == 0 &&
        emf_uint(record, 12, 4) == 0 else {
        @failure.reject(
          "unsupported-image", "EMF mapping origins require support",
        )
      }
    }
    18 => {
      guard size == 12 && emf_uint(record, 8, 4) == 1 else {
        @failure.reject(
          "unsupported-image", "Opaque EMF text backgrounds require support",
        )
      }
      self.dc = { ..self.dc, transparent: true, }
    }
    19 | 22 | 24 | 25 | 98 => {
      guard size == 12 else {
        @failure.reject("invalid-image", "Invalid EMF drawing state")
      }
      let value = emf_uint(record, 8, 4)
      match kind {
        19 => {
          guard [1, 2].contains(value) else {
            @failure.reject("invalid-image", "Invalid EMF polygon fill mode")
          }
          self.dc = { ..self.dc, odd: value == 1, }
        }
        22 => {
          guard [0, 24].contains(value) else {
            @failure.reject(
              "unsupported-image", "EMF text alignment requires support",
            )
          }
          self.dc = { ..self.dc, baseline: value == 24, }
        }
        24 => self.dc = { ..self.dc, color: emf_color(value), }
        25 => ignore(emf_color(value))
        _ => {
          guard value == 1 else {
            @failure.reject(
              "unsupported-image", "EMF color management requires support",
            )
          }
        }
      }
    }
    28 => {
      guard size == 8 && self.dc.clip is None else {
        @failure.reject(
          "unsupported-image", "EMF meta-region promotion requires support",
        )
      }
    }
    33 => {
      guard size == 8 && self.stack.length() < 32 else {
        @failure.reject(
          "limit-exceeded", "EMF device context stack exceeds budget",
        )
      }
      self.stack.push(self.dc)
    }
    34 => {
      guard size == 12 && emf_uint(record, 8, 4) == -1 && !self.stack.is_empty() else {
        @failure.reject(
          "invalid-image", "Invalid EMF device context restoration",
        )
      }
      self.dc = self.stack.pop().unwrap()
    }
    36 => {
      guard size == 36 && emf_uint(record, 32, 4) == 2 else {
        @failure.reject(
          "unsupported-image", "EMF transform mode requires support",
        )
      }
      let v = Array::makei(6, i => {
        Float::reinterpret_from_int(emf_uint(record, 8 + i * 4, 4)).to_double()
      })
      guard v.all(n => !n.is_nan() && !n.is_inf() && n.abs() <= 1000000000) &&
        v[0] > 0 &&
        v[0] == v[3] &&
        v[1] == 0 &&
        v[2] == 0 else {
        @failure.reject(
          "unsupported-image", "EMF requires an axis-aligned uniform transform",
        )
      }
      let world = self.dc.world.then({
        a: v[0],
        b: 0,
        c: 0,
        d: v[3],
        e: v[4],
        f: v[5],
      })
      ignore(world.inverse())
      self.dc = { ..self.dc, world, }
    }
    37 => {
      guard size == 12 else {
        @failure.reject("invalid-image", "Invalid EMF object selection")
      }
      let index = emf_uint(record, 8, 4)
      if index < 0 {
        match index & 0x7fffffff {
          0 => self.dc = { ..self.dc, brush: "ffffff", }
          5 => self.dc = { ..self.dc, brush: "", }
          7 => self.dc = { ..self.dc, pen: ("000000", 0, emf_pen_style()), }
          8 => self.dc = { ..self.dc, pen: ("", 0, emf_pen_style()), }
          10 | 11 | 12 | 13 | 14 | 16 | 17 =>
            self.dc = { ..self.dc, font: None, }
          _ =>
            @failure.reject("unsupported-image", "Unsupported EMF stock object")
        }
      } else {
        match self.objects.get(index) {
          Some(Font(key, size)) =>
            self.dc = { ..self.dc, font: Some((key, size)), }
          Some(Brush(fill)) => self.dc = { ..self.dc, brush: fill, }
          Some(Pen(color, width, style)) =>
            self.dc = { ..self.dc, pen: (color, width, style), }
          None =>
            @failure.reject("invalid-image", "Unknown EMF object selection")
        }
      }
    }
    39 => {
      guard size == 24 &&
        emf_uint(record, 12, 4) == 0 &&
        emf_uint(record, 20, 4) == 0 else {
        @failure.reject("unsupported-image", "EMF brush requires a solid color")
      }
      self.object(
        emf_uint(record, 8, 4),
        Brush(emf_color(emf_uint(record, 16, 4))),
      )
    }
    40 => {
      guard size == 12 && self.objects.contains(emf_uint(record, 8, 4)) else {
        @failure.reject("invalid-image", "Unknown EMF object deletion")
      }
      self.objects.remove(emf_uint(record, 8, 4))
    }
    70 => self.comment(record)
    75 => {
      guard size == 64 &&
        emf_uint(record, 8, 4) == 48 &&
        emf_uint(record, 12, 4) == 5 &&
        emf_uint(record, 16, 4) == 32 &&
        emf_uint(record, 20, 4) == 1 &&
        emf_uint(record, 24, 4) == 1 &&
        emf_uint(record, 28, 4) == 16 &&
        [0, 4, 8, 12].all(at => {
          emf_uint(record, 32 + at, 4) == emf_uint(record, 48 + at, 4)
        }) else {
        @failure.reject(
          "unsupported-image", "EMF clipping requires a single copied rectangle",
        )
      }
      self.dc = { ..self.dc, clip: Some(emf_rect(record, 48)), }
    }
    76 => {
      guard size == 100 &&
        emf_uint(record, 40, 4) == 0x00aa0029 &&
        [84, 88, 92, 96].all(at => emf_uint(record, at, 4) == 0) else {
        @failure.reject(
          "unsupported-image", "EMF raster operation requires support",
        )
      }
    }
    82 => self.font_record(record)
    84 => self.label(record)
    95 => {
      guard size == 56 &&
        emf_uint(record, 12, 4) == 56 &&
        emf_uint(record, 16, 4) == 0 &&
        emf_uint(record, 20, 4) == 56 &&
        emf_uint(record, 24, 4) == 0 &&
        emf_uint(record, 28, 4) == 0x10200 &&
        emf_uint(record, 32, 4) > 0 &&
        emf_uint(record, 36, 4) == 0 &&
        emf_uint(record, 44, 4) == 0 &&
        emf_uint(record, 48, 4) == 0 else {
        @failure.reject(
          "unsupported-image", "EMF pen requires a solid geometric stroke",
        )
      }
      self.object(
        emf_uint(record, 8, 4),
        Pen(
          emf_color(emf_uint(record, 40, 4)),
          emf_uint(record, 32, 4).to_double(),
          { ..emf_pen_style(), cap: 0, },
        ),
      )
    }
    _ => return false
  }
  true
}
