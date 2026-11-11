///|
pub(all) struct MetafileText {
  text : String
  font : String
  size : Double
  color : String
  x : Double
  y : Double
  advances : Array[Double]
  clip : Border?
}

///|
pub(all) enum MetafileCommand {
  Bitmap(String, Border, Int32, Int32, Bytes)
  Label(MetafileText)
  Vector(Array[PathSegment], String, String, Double, PathStyle, Border?)
}

///|
pub struct Metafile {
  identity : String
  bounds : Border
  commands : Array[MetafileCommand]
  primitives : Array[PositionedPrimitive]
  preview : (String, Int32, Int32, Bytes)?
}

///|
/// Native image content retains logical coordinates and decoded bitmap resources.
/// ```mbt check
/// test "Metafile frames retain logical bitmap resources and bounds" {
///   let bounds : @layout.Border = { x: 0, y: 0, width: 10, height: 10, }
///   let file = @layout.Metafile::new(bounds, [
///     @layout.Bitmap("pixel", bounds, 1, 1, b"\xff\x00\x00\xff"),
///   ])
///   let frame : @layout.DrawingFrame = {
///     width: 20,
///     height: 20,
///     effectExtent: (0, 0, 0, 0),
///     anchor: None,
///     content: @layout.Metafile(file),
///   }
///   frame.validate()
///   assert_eq(file.text(), "")
///   assert_eq(file.image_keys(), ["pixel"])
///   let probe = @layout.TextProbe::new()
///   defer probe.close()
///   assert_eq(file.positioned(20, 20, probe, Map([])).length(), 5)
/// }
/// ```
pub fn Metafile::new(
  bounds : Border,
  commands : Array[MetafileCommand],
) -> Metafile raise @failure.Failure {
  let result = {
    identity: "metafile",
    bounds,
    commands: commands.map(command => {
      match command {
        Label(text) => Label({ ..text, advances: text.advances.copy(), })
        Vector(path, fill, stroke, width, pen, clip) =>
          Vector(
            path.copy(),
            fill,
            stroke,
            width,
            { ..pen, dash: pen.dash.copy(), },
            clip,
          )
        _ => command
      }
    }),
    primitives: [],
    preview: None,
  }
  result.validate()
  let metadata : Array[Json] = commands.map(command => {
    match command {
      Bitmap(key, rect, width, height, rgba) =>
        {
          "key": key,
          "rect": rect,
          "width": width,
          "height": height,
          "rgba": @crypto.sha256(rgba).iter().map(b => b.to_int()).to_array(),
        }
      Label(text) =>
        {
          "text": text.text,
          "font": text.font,
          "size": text.size,
          "color": text.color,
          "x": text.x,
          "y": text.y,
          "advances": text.advances,
          "clip": text.clip,
        }
      Vector(path, fill, stroke, width, pen, clip) =>
        {
          "path": path,
          "fill": fill,
          "stroke": stroke,
          "width": width,
          "fillAlpha": pen.fillAlpha,
          "strokeAlpha": pen.strokeAlpha,
          "dash": pen.dash,
          "cap": pen.cap,
          "join": pen.join,
          "miter": pen.miter,
          "evenOdd": pen.evenOdd,
          "clip": clip,
        }
    }
  })
  let descriptor : Json = { "bounds": bounds, "commands": metadata }
  let identity = StringBuilder()
  identity.write_string("metafile:")
  for byte in @crypto.sha256(@utf8.encode(descriptor.stringify())) {
    identity.write_char(
      "0123456789abcdef"[byte.to_int() >> 4].to_char().unwrap(),
    )
    identity.write_char(
      "0123456789abcdef"[byte.to_int() & 15].to_char().unwrap(),
    )
  }
  { ..result, identity: identity.to_string(), }
}

///|
fn Metafile::validate(self : Metafile) -> Unit raise @failure.Failure {
  guard !self.identity.is_empty() &&
    self.identity.length() <= 256 &&
    self.commands.length() <= 8192 &&
    [self.bounds.x, self.bounds.y, self.bounds.width, self.bounds.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
    }) &&
    self.bounds.width >= 1 &&
    self.bounds.height >= 1 else {
    @failure.reject("invalid-image", "Invalid metafile bounds or identity")
  }
  let mut pixels = 0L
  let mut units = 0
  let mut segments = 0
  let keys : Map[String, Unit] = Map([])
  for command in self.commands {
    match command {
      Bitmap(key, rect, width, height, rgba) => {
        pixels += width.to_int64() * height.to_int64()
        guard !key.is_empty() &&
          !keys.contains(key) &&
          key.length() <= 256 &&
          width > 0 &&
          height > 0 &&
          width <= ImageDimension &&
          height <= ImageDimension &&
          pixels <= (ImageBytes / 4).to_int64() &&
          width.to_int64() * height.to_int64() * 4 == rgba.length().to_int64() &&
          [rect.x, rect.y, rect.width, rect.height].all(v => {
            !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
          }) &&
          rect.width > 0 &&
          rect.height > 0 else {
          @failure.reject("invalid-image", "Invalid metafile bitmap")
        }
        keys[key] = ()
      }
      Label(text) => {
        units += text.text.length()
        guard units <= 32767 &&
          text.text.length() == text.advances.length() &&
          !text.font.is_empty() &&
          text.font.length() <= 256 &&
          text.color.length() == 6 &&
          text.color.iter().all(c => c.is_ascii_hexdigit()) &&
          text.size > 0 &&
          text.size <= 1024 &&
          !text.size.is_nan() &&
          [text.x, text.y, ..text.advances].all(v => {
            !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
          }) else {
          @failure.reject("invalid-image", "Invalid metafile label")
        }
        if text.clip is Some(rect) {
          guard [rect.x, rect.y, rect.width, rect.height].all(v => {
              !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
            }) &&
            rect.width >= 0 &&
            rect.height >= 0 else {
            @failure.reject("invalid-image", "Invalid metafile text clip")
          }
        }
        let mut x = text.x
        for advance in text.advances {
          x += advance
          guard x.abs() <= 1000000000 else {
            @failure.reject(
              "limit-exceeded", "Metafile label advances exceed coordinate budget",
            )
          }
        }
      }
      Vector(path, fill, stroke, width, pen, clip) => {
        segments += path.length()
        pen.validate()
        guard segments <= 65536 &&
          !path.is_empty() &&
          [fill, stroke].all(c => {
            c.is_empty() ||
            (c.length() == 6 && c.iter().all(c => c.is_ascii_hexdigit()))
          }) &&
          width >= 0 &&
          width <= 1000000000 else {
          @failure.reject("invalid-image", "Invalid metafile path or pen")
        }
        let mut started = false
        for segment in path {
          let points = match segment {
            Move(x, y) => {
              started = true
              [x, y]
            }
            Line(x, y) => [x, y]
            Cubic(a, b, c, d, x, y) => [a, b, c, d, x, y]
            Close => []
          }
          guard started &&
            points.all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000) else {
            @failure.reject(
              "invalid-image", "Invalid metafile path coordinates",
            )
          }
        }
        if clip is Some(rect) {
          guard [rect.x, rect.y, rect.width, rect.height].all(v => {
              !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
            }) &&
            rect.width >= 0 &&
            rect.height >= 0 else {
            @failure.reject("invalid-image", "Invalid metafile path clip")
          }
        }
      }
    }
  }
}

///|
pub fn Metafile::text(self : Metafile) -> String {
  self.commands
  .filter_map(command => {
    match command {
      Label(text) => Some(text.text)
      _ => None
    }
  })
  .join("\n")
}

///|
pub fn Metafile::image_keys(self : Metafile) -> Array[String] {
  let keys = self.commands.filter_map(command => {
    match command {
      Bitmap(key, _, _, _, _) => Some(key)
      _ => None
    }
  })
  if self.preview is Some((key, _, _, _)) {
    keys.push(key)
  }
  keys
}

///|
pub impl ToJson for Metafile with fn to_json(self) {
  {
    "identity": self.identity,
    "text": self.text(),
    "images": self.image_keys(),
  }
}

///|
pub extend Metafile with ToJson::{to_json}

///|
fn Metafile::copy(self : Metafile) -> Metafile {
  {
    ..self,
    commands: self.commands.copy(),
    primitives: self.primitives.copy(),
  }
}

///|
fn Metafile::supply_images(
  self : Metafile,
  images : Images,
) -> Unit raise @failure.Failure {
  for command in self.commands {
    if command is Bitmap(key, _, width, height, rgba) {
      if images.entries.get(key) is Some(image) {
        guard image.width == width && image.height == height else {
          @failure.reject(
            "invalid-image", "Decoded metafile bitmap dimensions changed",
          )
        }
      } else {
        images.add(key, width, height, rgba)
      }
    }
  }
  if self.preview is Some((key, width, height, rgba)) {
    if images.entries.get(key) is Some(image) {
      guard image.width == width && image.height == height && image.rgba == rgba else {
        @failure.reject(
          "invalid-image", "Generated metafile preview changed through the host",
        )
      }
    }
    images.add(key, width, height, rgba)
  }
}

///|
fn Metafile::prepare(
  self : Metafile,
  frame : DrawingFrame,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  let primitives : Array[PositionedPrimitive] = []
  for command in self.commands {
    match command {
      Bitmap(key, rect, _, _, _) =>
        primitives.push(
          Image(
            {
              key,
              interpolate: Some(true),
              x: rect.x,
              y: rect.y,
              width: rect.width,
              height: rect.height,
            },
            1,
          ),
        )
      Label(text) => {
        let primary = probe.font_index(
          font_profile_identity(profile, text.font).unwrap_or(text.font),
        )
        // ONLYOFFICE's EMF SVG preview places TA_TOP text at the logical font height.
        let baseline = text.y + text.size
        let batch = probe.shape(
          text.text,
          text.size,
          text.color,
          primary~,
          base=0,
          kerning="none",
        )
        guard batch.diagnostics.is_empty() else {
          @failure.reject(
            "missing-font", "Metafile font lacks required label glyphs",
          )
        }
        let offsets : Array[Double] = [0]
        for advance in text.advances {
          offsets.push(offsets.last().unwrap() + advance)
        }
        let origins : Map[Int32, Double] = Map([])
        // GDI supplies UTF-16 advances; retain shaping within each source cluster.
        let glyphs = probe
          .bold_glyphs(batch.glyphs, text.font)
          .map(glyph => {
            let origin = origins.get_or_init(glyph.cluster, () => {
              glyph.x - glyph.xOffset.to_double() * glyph.scale
            })
            { ..glyph, x: offsets[glyph.cluster] + glyph.x - origin, }
          })
        if text.clip is Some(rect) {
          primitives.push(Clip(rect))
        }
        primitives.push(
          Text({
            text: text.text,
            runs: [
              {
                color: text.color,
                text: text.text,
                glyphs,
                x: text.x,
                baseline,
              },
            ],
          }),
        )
        if text.clip is Some(_) {
          primitives.push(Restore)
        }
      }
      Vector(path, fill, stroke, width, pen, clip) => {
        if clip is Some(rect) {
          primitives.push(Clip(rect))
        }
        primitives.push(Path(path, fill, stroke, width, pen))
        if clip is Some(_) {
          primitives.push(Restore)
        }
      }
    }
  }
  { ..frame, content: Metafile({ ..self, primitives, }), }
}

///|
fn Metafile::cache_units(self : Metafile) -> Int32 {
  let mut units = positioned_cache_units([self.identity], self.primitives)
  if self.preview is Some((_, _, _, rgba)) {
    units += rgba.length()
  }
  for command in self.commands {
    units += match command {
      Bitmap(key, _, _, _, rgba) => key.length() + rgba.length()
      Label(text) =>
        text.text.length() + text.advances.length() + text.font.length()
      Vector(path, _, _, _, pen, _) => path.length() * 8 + pen.dash.length()
    }
    if units > 1048576 {
      return 1048577
    }
  }
  units
}

///|
/// Shapes native metafile text and paths in the requested frame.
pub fn Metafile::positioned(
  self : Metafile,
  width : Double,
  height : Double,
  probe : TextProbe,
  profile : Map[String, String],
) -> Array[PositionedPrimitive] raise @failure.Failure {
  let frame : DrawingFrame = {
    width,
    height,
    effectExtent: (0, 0, 0, 0),
    anchor: None,
    content: Metafile(self),
  }
  frame.validate()
  let ready = self.prepare(frame, probe, profile)
  let out = []
  if ready.content is Metafile(file) {
    file.paint(
      {
        start: 0,
        level: 0,
        x: 0,
        y: 0,
        width,
        height,
        effectExtent: (0, 0, 0, 0),
        anchor: None,
        content: ready.content,
      },
      out,
    )
  }
  out
}

///|
fn Metafile::paint(
  self : Metafile,
  frame : PlacedDrawingFrame,
  out : Array[PositionedPrimitive],
) -> Unit {
  let sx = frame.width / self.bounds.width
  let sy = frame.height / self.bounds.height
  out.push(
    Clip({ x: frame.x, y: frame.y, width: frame.width, height: frame.height, }),
  )
  out.push(
    Transform({
      a: sx,
      b: 0,
      c: 0,
      d: sy,
      e: frame.x - self.bounds.x * sx,
      f: frame.y - self.bounds.y * sy,
    }),
  )
  out.append(self.primitives)
  out.push(Restore)
  out.push(Restore)
}
