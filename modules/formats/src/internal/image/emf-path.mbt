///|
fn EmfReader::rect(self : EmfReader, rect : @layout.Border) -> @layout.Border {
  let (x, y) = self.dc.world.point(rect.x, rect.y)
  {
    x,
    y,
    width: rect.width * self.dc.world.a,
    height: rect.height * self.dc.world.d,
  }
}

///|
fn EmfReader::vector(
  self : EmfReader,
  path : Array[@layout.PathSegment],
  stroke : Bool,
) -> Unit {
  let (color, width, style) = self.dc.pen
  self.commands.push(
    @layout.Vector(
      path,
      self.dc.brush,
      if stroke {
        color
      } else {
        ""
      },
      if width == 0 {
        1
      } else {
        width * self.dc.world.a
      },
      { ..style, evenOdd: self.dc.odd, },
      self.dc.clip,
    ),
  )
}

///|
fn EmfReader::path_record(
  self : EmfReader,
  kind : Int32,
  record : Bytes,
) -> Bool raise @failure.Failure {
  let size = record.length()
  match kind {
    59 => {
      guard size == 8 && !self.path_open && !self.path_ready else {
        @failure.reject("invalid-image", "Invalid EMF path start")
      }
      self.path_open = true
      self.path = []
    }
    60 => {
      guard size == 8 && self.path_open && !self.path.is_empty() else {
        @failure.reject("invalid-image", "Invalid EMF path end")
      }
      self.path_open = false
      self.path_ready = true
    }
    61 => {
      guard size == 8 && self.path_open && !self.path.is_empty() else {
        @failure.reject("invalid-image", "Invalid EMF path closure")
      }
      self.path.push(@layout.Close)
    }
    27 | 54 => {
      guard size == 16 &&
        self.path_open &&
        (kind == 27 || !self.path.is_empty()) else {
        @failure.reject("unsupported-image", "EMF line requires an open path")
      }
      let (x, y) = self.dc.world.point(
        emf_uint(record, 8, 4).to_double(),
        emf_uint(record, 12, 4).to_double(),
      )
      self.path.push(
        if kind == 27 {
          @layout.Move(x, y)
        } else {
          @layout.Line(x, y)
        },
      )
    }
    62 | 63 => {
      guard size == 24 && self.path_ready && !self.path_open else {
        @failure.reject("invalid-image", "EMF painted path is incomplete")
      }
      self.vector(self.path, kind == 63)
      self.path = []
      self.path_ready = false
    }
    86 | 88 | 89 => {
      let count = emf_uint(record, 24, 4)
      guard count > 0 &&
        count <= 65536 - self.segments &&
        count <= (size - 28) / 4 &&
        size == 28 + count * 4 &&
        (if kind == 86 {
          !self.path_open && !self.path_ready && count >= 3
        } else {
          self.path_open &&
          !self.path.is_empty() &&
          (kind != 88 || count % 3 == 0)
        }) else {
        @failure.reject("invalid-image", "Invalid EMF polygon or curve bounds")
      }
      let points = Array::makei(count, i => {
        self.dc.world.point(
          (emf_uint(record, 28 + i * 4, 2) << 16 >> 16).to_double(),
          (emf_uint(record, 30 + i * 4, 2) << 16 >> 16).to_double(),
        )
      })
      if kind == 86 {
        let path : Array[@layout.PathSegment] = points.map(p => {
          @layout.Line(p.0, p.1)
        })
        path[0] = @layout.Move(points[0].0, points[0].1)
        path.push(@layout.Close)
        self.vector(path, true)
      } else if kind == 88 {
        for at = 0; at < count; at = at + 3 {
          self.path.push(
            @layout.Cubic(
              points[at].0,
              points[at].1,
              points[at + 1].0,
              points[at + 1].1,
              points[at + 2].0,
              points[at + 2].1,
            ),
          )
        }
      } else {
        self.path.append(points.map(p => @layout.Line(p.0, p.1)))
      }
      self.segments += count
    }
    _ => return false
  }
  self.segments += 1
  guard self.segments <= 65536 else {
    @failure.reject("limit-exceeded", "EMF path segments exceed budget")
  }
  true
}
