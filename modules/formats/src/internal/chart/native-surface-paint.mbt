///|
fn surface_scale(
  data : @layout.ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let (low, high, step) = line_scale(data)
  let values = data.series
    .map(series => series.values.filter_map(value => value))
    .flatten()
  let minimum = values.fold(init=high, (minimum, value) => minimum.min(value))
  let maximum = values.fold(init=low, (maximum, value) => maximum.max(value))
  let high = if minimum < 0 && maximum <= 0 { high.min(0) } else { high }
  // Native 3D axes remove one outer tick when all data fits in the preceding interval.
  (
    if minimum < 0 && minimum >= low + step {
      low + step
    } else {
      low
    },
    if maximum > 0 && maximum <= high - step {
      high - step
    } else {
      high
    },
    step,
  )
}

///|
fn NativeSurface::paint(
  self : NativeSurface,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  guard source.kind == "surface" &&
    width >= 180 &&
    width <= 14400 &&
    height >= 150 &&
    height <= 14400 else {
    @failure.reject(
      "layout-overflow", "Native surface requires a bounded frame",
    )
  }
  let (data, _) = native_visible(
    Array::make(source.series.length(), ()),
    source,
    visible,
  )
  let out : Array[@layout.PositionedPrimitive] = []
  if !self.frame.0.is_empty() {
    out.push(Rectangle({ x: 0, y: 0, width, height, color: self.frame.0, }))
  }
  if !self.frame.1.0.is_empty() {
    out.push(
      Stroke({ x: 0, y: 0, width, height, }, self.frame.1.0, self.frame.1.1),
    )
  }
  if data.series.length() < 2 || data.categories.length() < 2 {
    return out
  }
  let (low, high, step) = surface_scale(data)
  let count = ((high - low) / step).round().to_int()
  guard count > 0 && count <= 600 else {
    @failure.reject("limit-exceeded", "Surface bands exceed axis budget")
  }
  let categories = data.categories.map(text => {
    line_label(text, self.category.text, probe, profile)
  })
  let labels = Array::makei(count + 1, i => {
    line_value_label(
      line_tick(low + i.to_double() * step).to_string(),
      self.value.text,
      probe,
      profile,
    )
  })
  let series_labels = data.series.map(series => {
    line_value_label(series.name, self.series_axis.text, probe, profile)
  })
  let title_height = fn(title : NativeLineTitle?) raise @failure.Failure {
    title
    .map(title => {
      line_value_label(title.text, title.style, probe, profile).height + 2.88
    })
    .unwrap_or(0)
  }
  let maximum = fn(blocks : Array[@layout.TextBlock]) {
    blocks.fold(init=0.0, (v, b) => v.max(b.widths[0]))
  }
  let category_height = categories.fold(init=0.0, (v, b) => v.max(b.height))
  let category_gap = line_offset(self.category.text, probe, profile)
  let value_gap = line_offset(self.value.text, probe, profile)
  let value_title_width = title_height(self.value.title) +
    (if self.value.title is Some(_) { 3.4 * 2.88 } else { 0 })
  let colors = Array::makei(count, i => {
    let mix = (i / 6 + 1).to_double() / ((count - 1) / 6 + 2).to_double() * 1.4 -
      0.7
    line_color_effect(
      self.palette[i % 6],
      if mix < 0 {
        1 + mix
      } else {
        1 - mix
      },
      mix >= 0,
    )
  })
  let legend_labels = self.legend
    .map(legend => {
      Array::makei(count, i => {
        line_label(
          line_tick(low + i.to_double() * step).to_string() +
          "-" +
          line_tick(low + (i + 1).to_double() * step).to_string(),
          circular_text_style(legend.text),
          probe,
          profile,
        )
      })
    })
    .unwrap_or([])
  let marker = self.legend
    .map(legend => circular_text_style(legend.text).size * 0.2 * 72 / 25.4)
    .unwrap_or(0)
  let legend_gap = marker * 0.7
  let legend_width = if self.legend is Some(_) {
    maximum(legend_labels) + marker + 3 * legend_gap
  } else {
    0
  }
  let margin = 16.0 * 0.75
  let left = self.plot
    .map(rect => rect.x * width + categories[0].widths[0] / 2)
    .unwrap_or(
      margin +
      value_title_width +
      (if !self.value_hidden && self.value_labels {
        maximum(labels) + value_gap * 1.5 + 0.1 * 72 / 25.4
      } else {
        0
      }),
    )
  let right = self.plot
    .map(rect => (rect.x + rect.width) * width)
    .unwrap_or(width - margin - legend_width) -
    categories.last().unwrap().widths[0] / 2
  // Native series-label bounds shrink the plot before the three-dimensional camera is fitted.
  let right = right.min(
    width -
    maximum(series_labels) / 2 -
    line_offset(self.series_axis.text, probe, profile) * 1.5,
  )
  let top = self.plot.map(rect => rect.y * height).unwrap_or(margin)
  let bottom = self.plot
    .map(rect => (rect.y + rect.height) * height)
    .unwrap_or(
      height -
      margin -
      title_height(self.category.title) -
      title_height(self.series_axis.title),
    ) -
    category_height -
    category_gap
  let plot : @layout.Border = {
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  }
  guard plot.width > 12 && plot.height > 12 else {
    @failure.reject("layout-overflow", "Surface labels exceed chart frame")
  }
  let projection = bar_projection(
    (width, height),
    plot,
    self.rotation,
    self.perspective,
    self.depth,
    data.series.length(),
    data.categories.length(),
    height_percent=self.height_percent.unwrap_or(plot.height / plot.width),
  )
  let point = fn(x : Double, y : Double, z : Double) {
    projection.point(x, y, z)
  }
  let floor_y = bottom
  for
    index, (paint, corners) in [
      (
        self.floor,
        [
          (left, floor_y, 0.0),
          (left, floor_y, projection.depth),
          (right, floor_y, projection.depth),
          (right, floor_y, 0.0),
        ],
      ),
      (
        self.side,
        [
          (left, floor_y, 0.0),
          (left, floor_y, projection.depth),
          (left, top, projection.depth),
          (left, top, 0.0),
        ],
      ),
      (
        self.back,
        [
          (left, floor_y, projection.depth),
          (right, floor_y, projection.depth),
          (right, top, projection.depth),
          (left, top, projection.depth),
        ],
      ),
    ] {
    if paint.0.is_empty() && paint.1.0.is_empty() {
      continue
    }
    let fill = if paint.0.is_empty() || index == 2 {
      paint.0
    } else {
      line_color_effect(paint.0, if index == 0 { 0.45 } else { 0.35 }, false)
    }
    out.push(bar_polygon(corners.map(p => point(p.0, p.1, p.2)), fill, paint.1))
  }
  let path = fn(
    points : Array[(Double, Double, Double)],
    pen : (String, Double),
  ) {
    out.push(
      line_path(
        points.mapi((i, p) => {
          if i == 0 {
            Move(p.0, p.1)
          } else {
            Line(p.0, p.1)
          }
        }),
        pen,
      ),
    )
  }
  for i in 0..<=count {
    let y = bottom - plot.height * i.to_double() / count.to_double()
    path(
      [
        point(left, y, 0),
        point(left, y, projection.depth),
        point(right, y, projection.depth),
      ],
      self.value.major,
    )
  }
  for
    i in 0..<(categories.length() + (if self.category_between { 1 } else { 0 })) {
    let x = left +
      plot.width *
      i.to_double() /
      (categories.length() - (if self.category_between { 0 } else { 1 })).to_double()
    path(
      [
        point(x, top, projection.depth),
        point(x, floor_y, projection.depth),
        point(x, floor_y, 0),
      ],
      self.category.major,
    )
  }
  let bands = surface_bands(
    data,
    projection,
    low,
    high,
    step,
    self.category_between,
  )
  for i, faces in bands {
    for points in faces {
      let fill = if self.wireframe { "" } else { colors[i] }
      let width = if self.wireframe { 0.75 } else { 0.13 * 72 / 25.4 }
      let face = bar_polygon(points, fill, (colors[i], width))
      if self.wireframe {
        out.push(face)
      } else {
        guard face is @layout.Path(path, _, _, _, style) else {
          @failure.reject("invalid-chart", "Surface band requires a polygon")
        }
        out.push(@layout.Path(path, fill, "", 0, style))
        // Share the native miter contour with vector shadows across output backends.
        out.push(
          @layout.Path(
            @layout.stroke_contour(path, width, "flat", "miter", 10),
            colors[i],
            "",
            0,
            style,
          ),
        )
      }
    }
  }
  path([point(left, floor_y, 0), point(right, floor_y, 0)], self.category.pen)
  path(
    [point(right, floor_y, 0), point(right, floor_y, projection.depth)],
    self.series_axis.pen,
  )
  if !self.value_hidden {
    path([point(left, bottom, 0), point(left, top, 0)], self.value.pen)
  }
  if self.category.major_tick == "out" {
    let ticks : Array[@layout.PathSegment] = []
    let intervals = categories.length() -
      (if self.category_between { 0 } else { 1 })
    for i in 0..<=categories.length() {
      let x = left +
        plot.width * i.min(intervals).to_double() / intervals.to_double()
      let a = point(x, floor_y, 0)
      let b = point(x, floor_y + 3.75, 0)
      ticks.append([Move(a.0, a.1), Line(b.0, b.1)])
    }
    out.push(
      line_path(
        ticks,
        (
          if self.category.pen.0 == "000000" {
            "868686"
          } else {
            self.category.pen.0
          },
          self.category.pen.1,
        ),
      ),
    )
  }
  if self.series_axis.major_tick == "out" {
    for i in 0..<=data.series.length() {
      let p = point(
        right,
        floor_y,
        projection.depth * i.to_double() / data.series.length().to_double(),
      )
      path(
        [p, (p.0 + 3.75, p.1, p.2)],
        (
          if self.series_axis.pen.0 == "000000" {
            "868686"
          } else {
            self.series_axis.pen.0
          },
          self.series_axis.pen.1,
        ),
      )
    }
  }
  for i, label in categories {
    let x = left +
      plot.width *
      (i.to_double() + (if self.category_between { 0.5 } else { 0.0 })) /
      (categories.length() - (if self.category_between { 0 } else { 1 })).to_double()
    let p = point(x, floor_y, 0)
    line_place(out, label, p.0 - label.widths[0] / 2, p.1 + category_gap)
  }
  for i, label in series_labels {
    let p = point(
      right,
      floor_y,
      projection.depth *
      i.to_double() /
      (series_labels.length() - 1).to_double(),
    )
    line_place(out, label, p.0 + 10, p.1 - label.height / 2)
  }
  if !self.value_hidden && self.value_labels {
    for i, label in labels {
      let p = point(
        left,
        bottom - plot.height * i.to_double() / count.to_double(),
        0,
      )
      line_place(
        out,
        label,
        p.0 - label.widths[0] - value_gap * 1.5,
        p.1 - label.height / 2,
      )
    }
  }
  let text_margin = 17.0 * 0.75
  if self.category.title is Some(title) {
    let y = height - text_margin - title_height(Some(title))
    line_caption_place(
      out,
      title,
      point((left + right) / 2, y, 0).0,
      y,
      probe,
      profile,
    )
  }
  if self.value.title is Some(title) {
    let caption_height = line_value_label(
        title.text,
        title.style,
        probe,
        profile,
      ).widths[0] +
      (1 + 2 * 1.016) * 72 / 25.4
    let y = point(text_margin, (top + bottom - caption_height) / 2, 0).1 +
      caption_height / 2 +
      1.44
    line_caption_place(
      out,
      { ..title, rotation: -1, },
      text_margin + 4.4 * 2.88 / 2,
      y,
      probe,
      profile,
    )
  }
  if self.series_axis.title is Some(title) && title.position is Some(_) {
    let y = height - text_margin - title_height(Some(title))
    line_caption_place(
      out,
      title,
      (left + right) / 2,
      y,
      probe,
      profile,
      frame=Some((width, height)),
    )
  }
  if self.legend is Some(legend) {
    let line_height = legend_labels.fold(init=0.0, (v, b) => v.max(b.height))
    let legend_height = line_height * count.to_double()
    let position = native_legend_position(
      legend.position,
      (width, height),
      (legend_width, legend_height),
      (width - text_margin / 2 - legend_width, (height - legend_height) / 2),
    )
    if !legend.fill.is_empty() {
      out.push(
        Rectangle({
          x: position.0,
          y: position.1,
          width: legend_width,
          height: legend_height,
          color: legend.fill,
        }),
      )
    }
    if !legend.pen.0.is_empty() {
      out.push(
        Stroke(
          {
            x: position.0,
            y: position.1,
            width: legend_width,
            height: legend_height,
          },
          legend.pen.0,
          legend.pen.1,
        ),
      )
    }
    for i, label in legend_labels {
      let y = position.1 + i.to_double() * line_height
      out.push(
        Rectangle({
          x: position.0 + legend_gap,
          y: y + line_middle(label, probe) - marker / 2,
          width: marker,
          height: marker,
          color: colors[i],
        }),
      )
      line_place(out, label, position.0 + 2 * legend_gap + marker, y)
    }
  }
  out
}
