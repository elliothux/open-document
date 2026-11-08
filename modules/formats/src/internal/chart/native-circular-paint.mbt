///|
fn circular_text(
  text : String,
  style : @layout.TextStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.TextBlock raise @failure.Failure {
  if !text.contains("\n") {
    return line_label(text, style, probe, profile)
  }
  let block = probe.text_block(text, style, profile, 14400, false)
  {
    ..block,
    widths: text
    .split("\n")
    .to_array()
    .map(line => line_label(line.to_owned(), style, probe, profile).widths[0]),
  }
}

///|
fn circular_place_centered(
  out : Array[@layout.PositionedPrimitive],
  block : @layout.TextBlock,
  x : Double,
  y : Double,
) -> Unit {
  let width = block.widths.fold(init=0.0, (a, b) => a.max(b))
  for index, line in block.lines {
    // Native centered paragraphs include a one-millimeter content-width guard.
    let left = x + (width - block.widths[index]) / 2 + 0.5 * 72 / 25.4
    out.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: left, f: y, }))
    out.append(line)
    out.push(Restore)
  }
}

///|
fn CircularPoint::paint(
  self : CircularPoint,
  out : Array[@layout.PositionedPrimitive],
  path : Array[@layout.PathSegment],
  print : Bool,
) -> Unit {
  // Native chart paths consume pens and brushes, and do not paint retained shadows.
  match self.fill {
    Solid(color) =>
      out.push(
        Path(path, color, self.pen.0, self.pen.1, {
          evenOdd: false,
          fillAlpha: 1,
          strokeAlpha: 1,
          dash: [],
          cap: 0,
          join: self.join,
          miter: 10,
        }),
      )
    Empty => out.push(line_path(path, self.pen, join=self.join))
    Bitmap(_, _, _) => {
      // Native printing omits one-curve sector fills; quadrant crossings retain their hatch.
      if print &&
        path
        .iter()
        .filter(segment => segment is Cubic(_, _, _, _, _, _))
        .count() <
        2 {
        if !self.pen.0.is_empty() {
          out.push(line_path(path, self.pen, join=self.join))
        }
        return
      }
      guard path is [Move(x, y), ..] else { return }
      let mut left = x
      let mut top = y
      let mut right = x
      let mut bottom = y
      // Native texture bounds include the cubic control points.
      for segment in path {
        let points = match segment {
          Move(x, y) | Line(x, y) => [(x, y)]
          Cubic(a, b, c, d, x, y) => [(a, b), (c, d), (x, y)]
          Close => []
        }
        for (x, y) in points {
          left = left.min(x)
          top = top.min(y)
          right = right.max(x)
          bottom = bottom.max(y)
        }
      }
      if right > left && bottom > top {
        out.push(ClipPath(path, false))
        out.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: left, f: top, }))
        self.fill.paint(out, {
          x: 0,
          y: 0,
          width: right - left,
          height: bottom - top,
        })
        out.push(Restore)
        out.push(Restore)
      }
      if !self.pen.0.is_empty() {
        out.push(line_path(path, self.pen, join=self.join))
      }
    }
  }
}

///|
fn circular_round_outline(
  rect : @layout.Border,
  pen : (String, Double),
) -> @layout.PositionedPrimitive {
  line_path(
    [
      Move(rect.x, rect.y),
      Line(rect.x + rect.width, rect.y),
      Line(rect.x + rect.width, rect.y + rect.height),
      Line(rect.x, rect.y + rect.height),
      Close,
    ],
    pen,
    join=1,
  )
}

///|
fn NativeCircular::paint(
  self : NativeCircular,
  data : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
  after_bar3d : Bool,
  print : Bool,
  implicit~ : Bool,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  data.validate_sources()
  guard ["pie", "doughnut"].contains(data.kind) &&
    width >= 32 &&
    height >= 32 &&
    width <= 14400 &&
    height <= 14400 else {
    @failure.reject("invalid-chart", "Invalid native circular frame")
  }
  let (data, styles) = native_visible(self.series, data, visible)
  let styles = if visible is Some(visible) {
    visible.values
    .filter(indices => !indices.is_empty())
    .mapi((index, indices) => {
      ..styles[index],
      points: indices.map(i => styles[index].points[i]),
    })
  } else {
    styles
  }
  let bounds : @layout.Border = { x: 0, y: 0, width, height, }
  // Native titles use seven logical pixels and the body top inset.
  let title_top = 7.0 * 72 / 96 + 0.508 * 72 / 25.4
  let pen = self.frame_pen.1 / 2
  let out : Array[@layout.PositionedPrimitive] = [
    Clip({ x: -pen, y: -pen, width: width + 2 * pen, height: height + 2 * pen, }),
    IntegerScreenGlyphs,
  ]
  self.frame_fill.paint(out, bounds)
  if !self.frame_pen.0.is_empty() {
    out.push(
      if self.frame_join == 1 {
        circular_round_outline(bounds, self.frame_pen)
      } else {
        Stroke(bounds, self.frame_pen.0, self.frame_pen.1)
      },
    )
  }
  let marker = self.legend
    .map(legend => legend.text.size * 0.2 * 72 / 25.4)
    .unwrap_or(0)
  let gap = marker * 0.7
  let labels = if styles.is_empty() {
    []
  } else {
    self.legend
    .map(legend => {
      data.categories.mapi((index, label) => {
        circular_text(
          if implicit && data.series[0].values[index] is None {
            ""
          } else {
            label
          },
          legend.text,
          probe,
          profile,
        )
      })
    })
    .unwrap_or([])
  }
  let legend_width = if labels.is_empty() {
    0.0
  } else {
    labels.fold(init=0.0, (w, block) => w.max(block.widths[0])) +
    marker +
    3 * gap
  }
  let legend_height = labels.fold(init=0.0, (h, block) => h.max(block.height))
  guard legend_height * labels.length().to_double() <= height else {
    @failure.reject(
      "layout-overflow", "Native circular legend exceeds its frame",
    )
  }
  let margin = (if after_bar3d { 17.0 } else { 14.0 }) * 0.75
  let plot : @layout.Border = {
    x: margin,
    y: margin,
    width: width - 2 * margin - legend_width,
    height: height - 2 * margin,
  }
  guard plot.width > 0 else {
    @failure.reject("layout-overflow", "Native circular plot exceeds its frame")
  }
  // Native circular plot backgrounds use the centered square and extend the top/left by one 96-dpi pixel.
  let side = plot.width.min(plot.height)
  let background : @layout.Border = {
    x: plot.x + (plot.width - side) / 2 - 0.75,
    y: plot.y + (plot.height - side) / 2 - 0.75,
    width: side + 0.75,
    height: side + 0.75,
  }
  self.plot_fill.paint(out, background)
  if !self.plot_pen.0.is_empty() {
    out.push(
      if self.plot_join == 1 {
        circular_round_outline(background, self.plot_pen)
      } else {
        Stroke(background, self.plot_pen.0, self.plot_pen.1)
      },
    )
  }
  let title = self.title.map(pair => {
    let block = circular_text(pair.0, pair.1, probe, profile)
    let left = (width - block.widths[0] - 2.25 * 72 / 25.4) / 2 +
      1.016 * 72 / 25.4
    (block, left)
  })
  if styles.is_empty() {
    if title is Some((block, left)) {
      circular_place_centered(out, block, left, title_top)
    }
    out.push(Restore)
    return out
  }
  let cx = plot.x + plot.width / 2
  let cy = plot.y + plot.height / 2
  let doughnut = data.kind == "doughnut"
  let explosion = styles[styles.length() - 1].explosion
  let radius = plot.width.min(plot.height) /
    2 /
    (1 + explosion / 100) *
    (if !doughnut &&
      styles[0].labels is Some(labels) &&
      !["ctr", "inEnd"].contains(labels.position) &&
      (labels.category || labels.series || labels.value || labels.percent) {
      0.85
    } else {
      1.0
    })
  let inner = if doughnut {
    radius * data.hole_size.unwrap_or(50).to_double() / 100
  } else {
    0.0
  }
  let step = (radius - inner) / styles.length().to_double()
  let pending : Array[
    (@layout.TextBlock, @layout.Border, (Double, Double), Double),
  ] = []
  for series_index, style in styles {
    let r = if doughnut {
      inner + step * (series_index + 1).to_double()
    } else {
      radius
    }
    let hole = if doughnut {
      inner + step * series_index.to_double()
    } else {
      0.0
    }
    let slices = data.pie_slices(series=series_index)
    for offset in 0..<slices.length() {
      let i = if doughnut { offset } else { slices.length() - 1 - offset }
      let (start, end) = slices[i]
      if end - start < 0.000000000000001 {
        continue
      }
      guard style.points.get(i) is Some(point) else {
        @failure.reject(
          "invalid-chart", "Native circular styles do not match values",
        )
      }
      let first = start + self.first_angle / 360
      let last = end + self.first_angle / 360
      let angle = (first + last) * @math.PI - @math.PI / 2
      let dx = @math.cos(angle)
      let dy = @math.sin(angle)
      let requested = if !doughnut || series_index == styles.length() - 1 {
        radius * point.explosion / 100
      } else {
        0.0
      }
      let shift = circular_explode_limit(first, last, r, cx, cy, width, height)
        .min(requested)
        .max(0)
      let x = cx + shift * dx
      let y = cy + shift * dy
      point.paint(
        out,
        @layout.circular_sector(first, last, x, y, r, inner=hole, office=true),
        print,
      )
      if style.labels is Some(labels) {
        let fields : Array[String] = []
        if labels.series {
          fields.push(data.series[series_index].name)
        }
        if labels.category {
          fields.push(data.categories[i])
        }
        if labels.value {
          fields.push(
            data.series[series_index].values[i].unwrap_or(0).to_string(),
          )
        }
        if labels.percent {
          let sign = if data.series[series_index].values[i].unwrap_or(0) < 0 {
            -1.0
          } else {
            1.0
          }
          fields.push(
            ((end - start) * 100 * sign + 0.5).floor().to_int().to_string() +
            "%",
          )
        }
        if fields.is_empty() {
          continue
        }
        let block = circular_text(
          fields.join(labels.separator),
          labels.text,
          probe,
          profile,
        )
        // Native label bounds include the content-width guard and fixed body insets.
        let w = block.widths.fold(init=0.0, (a, b) => a.max(b)) +
          2.25 * 72 / 25.4
        let h = block.height + 1.016 * 72 / 25.4
        let (left, top) = circular_label_position(
          first * 2 * @math.PI - @math.PI / 2,
          last * 2 * @math.PI - @math.PI / 2,
          r,
          hole,
          w,
          h,
          labels.position,
          doughnut,
        )
        let left = (x + left).max(0).min(width - w)
        let top = (y + top).max(0).min(height - h)
        pending.push(
          (block, { x: left, y: top, width: w, height: h, }, (x, y), angle),
        )
      }
    }
  }
  let boxes = pending.map(item => item.1)
  if !doughnut && styles[0].labels.bind(labels => labels.leader) is Some(pen) {
    let leader_min_squared = (width * width + height * height) / 10000
    for i, (_, _, (x, y), angle) in pending {
      let box = boxes[i]
      let (sx, sy) = (
        x + radius * @math.cos(angle),
        y + radius * @math.sin(angle),
      )
      let (tx, ty) = (
        sx.max(box.x).min(box.x + box.width),
        sy.max(box.y).min(box.y + box.height),
      )
      // Join the slice to the closest edge of an outside label.
      if (tx - x) * (tx - x) + (ty - y) * (ty - y) > radius * radius &&
        (tx - sx) * (tx - sx) + (ty - sy) * (ty - sy) >= leader_min_squared {
        out.push(line_path([Move(sx, sy), Line(tx, ty)], pen))
      }
    }
  }
  for i, (block, _, _, _) in pending {
    let box = boxes[i]
    circular_place_centered(
      out,
      block,
      box.x + 1.016 * 72 / 25.4,
      box.y + 0.508 * 72 / 25.4,
    )
  }

  if title is Some((block, left)) {
    circular_place_centered(out, block, left, title_top)
  }
  if self.legend is Some(legend) {
    let h = legend_height * labels.length().to_double()
    let (x, y) = native_legend_position(
      legend.position,
      (width, height),
      (legend_width, h),
      (width - legend_width - 5.25, (height - h) / 2),
    )
    let rect : @layout.Border = { x, y, width: legend_width, height: h, }
    if !legend.fill.is_empty() {
      out.push(
        Rectangle({ x, y, width: legend_width, height: h, color: legend.fill, }),
      )
    }
    if !legend.pen.0.is_empty() {
      out.push(
        if legend.join == 1 {
          circular_round_outline(rect, legend.pen)
        } else {
          FractionalScreenStroke(rect, legend.pen.0, legend.pen.1)
        },
      )
    }
    for i, label in labels {
      let at = y + i.to_double() * legend_height
      let marker_rect : @layout.Border = {
        x: x + gap,
        y: at + line_middle(label, probe) - marker / 2,
        width: marker,
        height: marker,
      }
      if styles[0].points.get(i) is Some(point) {
        out.push(
          Transform({
            a: 1,
            b: 0,
            c: 0,
            d: 1,
            e: marker_rect.x,
            f: marker_rect.y,
          }),
        )
        let marker_bounds : @layout.Border = {
          x: 0,
          y: 0,
          width: marker,
          height: marker,
        }
        if data.series[0].values[i] is None && !point.explicit_fill {
          guard worksheet_color_valid(point.legend_fill) else {
            @failure.reject(
              "missing-theme", "Missing native legend theme palette",
            )
          }
          out.push(
            Rectangle({
              x: 0,
              y: 0,
              width: marker,
              height: marker,
              color: point.legend_fill,
            }),
          )
        } else {
          point.fill.paint(out, marker_bounds)
          if !point.pen.0.is_empty() {
            out.push(
              if point.join == 1 {
                circular_round_outline(marker_bounds, point.pen)
              } else {
                FractionalScreenStroke(marker_bounds, point.pen.0, point.pen.1)
              },
            )
          }
        }
        out.push(Restore)
      }
      line_place(out, label, x + 2 * gap + marker, at)
    }
  }
  out.push(Restore)
  out
}

///|
fn circular_explode_limit(
  start : Double,
  end : Double,
  radius : Double,
  cx : Double,
  cy : Double,
  width : Double,
  height : Double,
) -> Double {
  let first = start * 2 * @math.PI - @math.PI / 2
  let last = end * 2 * @math.PI - @math.PI / 2
  let angle = (first + last) / 2
  let angles = [first, last]
  for i in -8..<=12 {
    let a = i.to_double() * @math.PI / 2
    if a >= first && a <= last {
      angles.push(a)
    }
  }
  let xs = angles.map(angle => radius * @math.cos(angle))
  let ys = angles.map(angle => radius * @math.sin(angle))
  let dx = @math.cos(angle)
  let dy = @math.sin(angle)
  let mut limit = radius * 4
  if dx > 0 {
    limit = limit.min(
      (width - cx - xs.fold(init=xs[0], (a, b) => a.max(b))) / dx,
    )
  }
  if dx < 0 {
    limit = limit.min((-cx - xs.fold(init=xs[0], (a, b) => a.min(b))) / dx)
  }
  if dy > 0 {
    limit = limit.min(
      (height - cy - ys.fold(init=ys[0], (a, b) => a.max(b))) / dy,
    )
  }
  if dy < 0 {
    limit = limit.min((-cy - ys.fold(init=ys[0], (a, b) => a.min(b))) / dy)
  }
  limit.max(0)
}
