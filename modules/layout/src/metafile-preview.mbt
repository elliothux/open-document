///|
priv struct MetafileRaster {
  width : Int32
  height : Int32
  sx : Double
  sy : Double
  bounds : Border
  rgba : Array[Byte]
  mut work : Int64
}

///|
fn MetafileRaster::charge(
  self : MetafileRaster,
  width : Int32,
  height : Int32,
) -> Unit raise @failure.Failure {
  self.work += width.to_int64() * height.to_int64()
  guard self.work <= 67108864 else {
    @failure.reject(
      "limit-exceeded", "Metafile preview raster work exceeds budget",
    )
  }
}

///|
fn MetafileRaster::blend(
  self : MetafileRaster,
  x : Int32,
  y : Int32,
  red : Double,
  green : Double,
  blue : Double,
  alpha : Double,
) -> Unit {
  let at = (y * self.width + x) * 4
  let inverse = 1.0 - alpha
  self.rgba[at] = (red * alpha + self.rgba[at].to_double() * inverse)
    .round()
    .to_int()
    .clamp(min=0, max=255)
    .to_byte()
  self.rgba[at + 1] = (green * alpha + self.rgba[at + 1].to_double() * inverse)
    .round()
    .to_int()
    .clamp(min=0, max=255)
    .to_byte()
  self.rgba[at + 2] = (blue * alpha + self.rgba[at + 2].to_double() * inverse)
    .round()
    .to_int()
    .clamp(min=0, max=255)
    .to_byte()
  self.rgba[at + 3] = (255.0 * alpha + self.rgba[at + 3].to_double() * inverse)
    .round()
    .to_int()
    .clamp(min=0, max=255)
    .to_byte()
}

///|
fn preview_intersection(a : Border, b : Border) -> Border {
  let x = a.x.max(b.x)
  let y = a.y.max(b.y)
  {
    x,
    y,
    width: ((a.x + a.width).min(b.x + b.width) - x).max(0),
    height: ((a.y + a.height).min(b.y + b.height) - y).max(0),
  }
}

///|
fn preview_coverage(clip : Border, x : Int32, y : Int32) -> Double {
  ((clip.x + clip.width).min(x.to_double() + 1) - clip.x.max(x.to_double())).max(
    0,
  ) *
  ((clip.y + clip.height).min(y.to_double() + 1) - clip.y.max(y.to_double())).max(
    0,
  )
}

///|
fn MetafileRaster::rect(self : MetafileRaster, rect : Border) -> Border {
  {
    x: (rect.x - self.bounds.x) * self.sx,
    y: (rect.y - self.bounds.y) * self.sy,
    width: rect.width * self.sx,
    height: rect.height * self.sy,
  }
}

///|
fn MetafileRaster::mask(
  self : MetafileRaster,
  path : String,
  style : @zeno.Style,
  matrix : @zeno.Transform,
  clip : Border,
  color : String,
  opacity : Double,
  dashes : Array[Double],
) -> Unit raise @failure.Failure {
  if path.is_empty() || color.is_empty() || opacity == 0 {
    return
  }
  let basic = @zeno.bounds(path, @zeno.Style::Fill(@zeno.NonZero), Some(matrix))
  guard [basic.min.x(), basic.min.y(), basic.max.x(), basic.max.y()].all(v => {
    !v.is_nan() && !v.is_inf() && v.abs() <= 1048576
  }) else {
    @failure.reject(
      "limit-exceeded", "Metafile preview path exceeds raster coordinates",
    )
  }
  let span = (basic.width() + basic.height()).max(1)
  self.charge(path.length(), span.ceil().to_int())
  if !dashes.is_empty() {
    let positive = dashes.filter(value => value > 0)
    guard !positive.is_empty() else {
      @failure.reject("invalid-image", "Empty metafile dash cycle")
    }
    let minimum = positive.fold(init=positive[0], (a, b) => a.min(b)) *
      self.sx.min(self.sy)
    let steps = span * dashes.length().to_double() / minimum
    guard steps * path.length().to_double() <= 67108864 else {
      @failure.reject(
        "limit-exceeded", "Metafile preview dash work exceeds budget",
      )
    }
    self.charge(path.length(), steps.ceil().to_int())
  }
  let bounds = @zeno.bounds(path, style, Some(matrix))
  guard [bounds.min.x(), bounds.min.y(), bounds.max.x(), bounds.max.y()].all(v => {
    !v.is_nan() && !v.is_inf() && v.abs() <= 1048576
  }) else {
    @failure.reject(
      "limit-exceeded", "Metafile preview path exceeds raster coordinates",
    )
  }
  let area = preview_intersection(clip, {
    x: bounds.min.x().floor(),
    y: bounds.min.y().floor(),
    width: bounds.max.x().ceil() - bounds.min.x().floor(),
    height: bounds.max.y().ceil() - bounds.min.y().floor(),
  })
  let left = area.x.floor().to_int().max(0)
  let top = area.y.floor().to_int().max(0)
  let width = (area.x + area.width).ceil().to_int().min(self.width) - left
  let height = (area.y + area.height).ceil().to_int().min(self.height) - top
  if width <= 0 || height <= 0 {
    return
  }
  self.charge(width, height)
  let (mask, _) = @zeno.Mask(path)
    .style(style)
    .transform(Some(matrix))
    .offset(@zeno.Vector(-left.to_double(), -top.to_double()))
    .size(width.reinterpret_as_uint(), height.reinterpret_as_uint())
    .render()
  let value = @string.parse_int(color, base=16) catch {
    _ => @failure.reject("invalid-image", "Invalid metafile preview color")
  }
  let red = ((value >> 16) & 255).to_double()
  let green = ((value >> 8) & 255).to_double()
  let blue = (value & 255).to_double()
  for y in 0..<height {
    for x in 0..<width {
      let alpha = mask[y * width + x].to_double() /
        255 *
        opacity *
        preview_coverage(clip, x + left, y + top)
      if alpha > 0 {
        self.blend(x + left, y + top, red, green, blue, alpha)
      }
    }
  }
}

///|
fn MetafileRaster::bitmap(
  self : MetafileRaster,
  rect : Border,
  width : Int32,
  height : Int32,
  rgba : Bytes,
  clip : Border,
) -> Unit raise @failure.Failure {
  let target = self.rect(rect)
  let area = preview_intersection(target, clip)
  let left = area.x.floor().to_int().max(0)
  let top = area.y.floor().to_int().max(0)
  let right = (area.x + area.width).ceil().to_int().min(self.width)
  let bottom = (area.y + area.height).ceil().to_int().min(self.height)
  if right <= left || bottom <= top {
    return
  }
  self.charge(right - left, bottom - top)
  for y in top..<bottom {
    let v = ((y.to_double() + 0.5 - target.y) /
    target.height *
    height.to_double() -
    0.5).clamp(min=0, max=height.to_double() - 1)
    let y0 = v.floor().to_int()
    for x in left..<right {
      let u = ((x.to_double() + 0.5 - target.x) /
      target.width *
      width.to_double() -
      0.5).clamp(min=0, max=width.to_double() - 1)
      let x0 = u.floor().to_int()
      let mut red = 0.0
      let mut green = 0.0
      let mut blue = 0.0
      let mut total_alpha = 0.0
      for iy in 0..<2 {
        for ix in 0..<2 {
          let weight = (if ix == 0 {
              1.0 - (u - x0.to_double())
            } else {
              u - x0.to_double()
            }) *
            (if iy == 0 {
              1.0 - (v - y0.to_double())
            } else {
              v - y0.to_double()
            })
          let at = (
              (y0 + iy).min(height - 1) * width + (x0 + ix).min(width - 1)
            ) *
            4
          let alpha = rgba[at + 3].to_double() / 255
          red += rgba[at].to_double() * alpha * weight
          green += rgba[at + 1].to_double() * alpha * weight
          blue += rgba[at + 2].to_double() * alpha * weight
          total_alpha += alpha * weight
        }
      }
      if total_alpha > 0 {
        self.blend(
          x,
          y,
          red / total_alpha,
          green / total_alpha,
          blue / total_alpha,
          total_alpha * preview_coverage(area, x, y),
        )
      }
    }
  }
}

///|
fn preview_path(path : Array[PathSegment]) -> String {
  let out = StringBuilder()
  for segment in path {
    match segment {
      Move(x, y) => out <+ "M\{x} \{y}"
      Line(x, y) => out <+ "L\{x} \{y}"
      Cubic(a, b, c, d, x, y) => out <+ "C\{a} \{b} \{c} \{d} \{x} \{y}"
      Close => out.write_char('Z')
    }
  }
  out.to_string()
}

///|
fn Metafile::prepare_preview(
  self : Metafile,
  frame : DrawingFrame,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  let prepared = self.prepare(frame, probe, profile)
  guard prepared.content is Metafile(file) else { return prepared }
  // ONLYOFFICE's stored-preview texture uses 300dpi, capped at 2000 pixels per edge.
  let nominal_width = (frame.width * 300 / 72).max(1)
  let nominal_height = (frame.height * 300 / 72).max(1)
  let scale = (2000.0 / nominal_width.max(nominal_height)).min(1)
  let width = (nominal_width * scale).to_int().max(10)
  let height = (nominal_height * scale).to_int().max(10)
  let raster : MetafileRaster = {
    width,
    height,
    sx: width.to_double() / self.bounds.width,
    sy: height.to_double() / self.bounds.height,
    bounds: self.bounds,
    rgba: Array::make(width * height * 4, 0),
    work: 0,
  }
  let full : Border = {
    x: 0,
    y: 0,
    width: width.to_double(),
    height: height.to_double(),
  }
  let mut clip = full
  let stack : Array[Border] = []
  let transform = @zeno.Transform(
    raster.sx,
    0,
    0,
    raster.sy,
    -self.bounds.x * raster.sx,
    -self.bounds.y * raster.sy,
  )
  let labels : Array[PositionedPrimitive] = []
  for primitive in file.primitives {
    match primitive {
      Clip(rect) => {
        stack.push(clip)
        clip = preview_intersection(clip, raster.rect(rect))
      }
      Restore => clip = stack.pop().unwrap()
      Image(image, _) =>
        for command in self.commands {
          if command is Bitmap(key, rect, source_width, source_height, rgba) &&
            key == image.key {
            raster.bitmap(rect, source_width, source_height, rgba, clip)
          }
        }
      Text(text) => {
        labels.push(primitive)
        for run in text.runs {
          for glyph in run.glyphs {
            let matrix = @zeno.Transform(
              glyph.scale * raster.sx,
              0,
              0,
              -glyph.scale * raster.sy,
              ((run.x + glyph.x - self.bounds.x) * raster.sx).trunc(),
              ((run.baseline + glyph.y - self.bounds.y) * raster.sy).trunc(),
            )
            raster.mask(
              probe.outlines[glyph.outline],
              @zeno.Style::Fill(@zeno.NonZero),
              matrix,
              clip,
              run.color,
              1,
              [],
            )
            if glyph.strokeWidth > 0 {
              raster.mask(
                probe.outlines[glyph.outline],
                @zeno.Style::Stroke(@zeno.Stroke::Stroke(glyph.strokeWidth)),
                matrix,
                clip,
                run.color,
                1,
                [],
              )
            }
          }
        }
      }
      Path(path, fill, stroke, line_width, pen) => {
        let path = preview_path(path)
        raster.mask(
          path,
          @zeno.Style::Fill(
            if pen.evenOdd {
              @zeno.EvenOdd
            } else {
              @zeno.NonZero
            },
          ),
          transform,
          clip,
          fill,
          pen.fillAlpha,
          [],
        )
        let style = @zeno.Stroke::Stroke(
            if line_width == 0 {
              1.0 / raster.sx.max(raster.sy)
            } else {
              line_width
            },
          )
          .join([@zeno.Miter, @zeno.Round, @zeno.Bevel][pen.join])
          .cap([@zeno.Butt, @zeno.Round, @zeno.Square][pen.cap])
          .miter_limit(pen.miter)
          .dash(pen.dash, 0)
        raster.mask(
          path,
          @zeno.Style::Stroke(style),
          transform,
          clip,
          stroke,
          pen.strokeAlpha,
          pen.dash,
        )
      }
      _ =>
        @failure.reject(
          "invalid-image", "Unexpected metafile preview primitive",
        )
    }
  }
  guard stack.is_empty() else {
    @failure.reject("invalid-image", "Unbalanced metafile preview clip")
  }
  for at in 0..<(width * height) {
    let alpha = raster.rgba[at * 4 + 3].to_int()
    for channel in 0..<3 {
      raster.rgba[at * 4 + channel] = (if alpha == 0 {
          255
        } else {
          (raster.rgba[at * 4 + channel].to_int() * 255 + alpha / 2) / alpha
        })
        .min(255)
        .to_byte()
    }
  }
  let rgba = Bytes::from_array(raster.rgba)
  let key = "metafile:preview:\{width}x\{height}:" +
    @crypto.sha256(rgba)
    .iter()
    .map(b => b.to_int().to_string(radix=16).pad_start(2, '0'))
    .join("")
  let primitives : Array[PositionedPrimitive] = [
    Image(
      {
        key,
        x: self.bounds.x,
        y: self.bounds.y,
        width: self.bounds.width,
        height: self.bounds.height,
        interpolate: Some(false),
      },
      1,
    ),
  ]
  if !labels.is_empty() {
    // Retain source label text in PDF extraction without painting it over the raster.
    primitives.push(Clip({ x: 0, y: 0, width: 0, height: 0, }))
    primitives.append(labels)
    primitives.push(Restore)
  }
  {
    ..prepared,
    content: Metafile({
      ..file,
      primitives,
      preview: Some((key, width, height, rgba)),
    }),
  }
}
