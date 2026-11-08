///|
priv struct NativeLineLegendLayout {
  labels : Array[@layout.TextBlock]
  styles : Array[NativeLineCurve]
  width : Double
  height : Double
  row_height : Double
  columns : Int32
  column_width : Double
}

///|
fn NativeLine::layout_legend(
  self : NativeLine,
  data : @layout.ChartData,
  styles : Array[NativeLineCurve],
  visible : @layout.ChartVisibility?,
  frame : (Double, Double),
  plot_height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> NativeLineLegendLayout raise @failure.Failure {
  let text = if self.point_legend {
    { ..self.legend_text, size: (self.legend_text.size * 2).round() / 2, }
  } else {
    self.legend_text
  }
  fn label(value : String) -> @layout.TextBlock raise @failure.Failure {
    if self.legend_bottom {
      line_value_label(value, text, probe, profile)
    } else {
      line_label(value, text, probe, profile)
    }
  }
  let (labels, styles) = if data.legend == "none" {
    ([], [])
  } else if self.point_legend {
    let series = styles[0]
    let values = data.series[0].values
    let indices = visible
      .map(visibility => visibility.values[0])
      .unwrap_or_else(() => Array::makei(values.length(), i => i))
    let labels = indices.mapi((i, source) => {
      label(if values[i] is Some(_) { (source + 1).to_string() } else { "" })
    })
    let styles = indices.mapi((i, _) => {
      let paint = if values[i] is Some(_) {
        let paint = series.points.get(i).unwrap_or(series.paint)
        {
          ..paint,
          marker_fill: paint.marker_pen.map(pen => pen.0).unwrap_or(""),
        }
      } else {
        { ..series.paint, marker: "none", color: "", }
      }
      { ..series, paint, }
    })
    (labels, styles)
  } else {
    (data.series.map(series => label(series.name)), styles)
  }
  let row_height = labels.fold(init=0.0, (height, block) => {
    height.max(block.height)
  })
  let marker_line = 7.7 * 72 / 25.4
  let gap = 0.5 * 72 / 25.4
  let entry_width = labels.fold(init=0.0, (width, block) => {
      width.max(block.widths[0])
    }) +
    marker_line +
    2 * gap
  let total_width = labels.fold(init=0.0, (width, block) => {
    width + block.widths[0] + marker_line + 2 * gap
  })
  if !self.point_legend || labels.is_empty() {
    guard row_height * labels.length().to_double() <= frame.1 else {
      @failure.reject(
        "layout-overflow", "Native line legend exceeds the chart frame",
      )
    }
    return {
      labels,
      styles,
      row_height,
      columns: 0,
      column_width: 0,
      width: if labels.is_empty() {
        0
      } else if self.legend_bottom {
        total_width + gap
      } else {
        entry_width + gap
      },
      height: row_height *
      (if self.legend_bottom { 1.0 } else { labels.length().to_double() }),
    }
  }
  let font = probe.font_info()[line_font(text, probe, profile)]
  // Native capacity excludes descent, but rows retain their full line height.
  let row_capacity = (row_height -
  font.descent.to_double().abs() * text.size / font.upem.to_double()).max(1)
  let (columns, limit, width) = if !self.legend_bottom {
    let height = self.plot
      .map(rect => rect.height * frame.1)
      .unwrap_or(plot_height)
    (1, height, entry_width + gap)
  } else if total_width <= frame.0 * 0.9 {
    (0, frame.1, total_width)
  } else {
    let columns = (frame.0 * 0.9 / entry_width).floor().to_int().max(1)
    let title_height = self.title
      .map(title => {
        line_value_label(title.text, title.style, probe, profile).height
      })
      .unwrap_or(0)
    (columns, (frame.1 - title_height) * 0.6, columns.to_double() * entry_width)
  }
  let rows = (limit / row_capacity)
    .floor()
    .min((frame.1 / row_height.max(1)).floor())
    .max(0)
    .to_int()
  let count = if columns == 0 {
    labels.length()
  } else {
    labels.length().min(rows * columns)
  }
  let height = if columns == 0 {
    row_height
  } else {
    ((count + columns - 1) / columns).to_double() * row_height
  }
  {
    labels: labels[:count].to_owned(),
    styles: styles[:count].to_owned(),
    row_height,
    columns,
    column_width: entry_width,
    width: if count == 0 {
      0
    } else {
      width
    },
    height,
  }
}

///|
fn NativeLine::paint_legend(
  self : NativeLine,
  out : Array[@layout.PositionedPrimitive],
  legend : @layout.Border,
  layout : NativeLineLegendLayout,
  probe : @layout.TextProbe,
) -> Unit raise @failure.Failure {
  let x = legend.x
  let y = legend.y
  let marker_line = 7.7 * 72 / 25.4
  let legend_gap = 0.5 * 72 / 25.4
  if !self.legend_fill.is_empty() {
    out.push(
      Rectangle({
        x: legend.x,
        y: legend.y,
        width: legend.width,
        height: legend.height,
        color: self.legend_fill,
      }),
    )
  }
  if !self.legend_pen.0.is_empty() {
    out.push(Stroke(legend, self.legend_pen.0, self.legend_pen.1))
  }
  let mut left = x
  for i, label in layout.labels {
    let x = if layout.columns == 0 {
      left
    } else {
      x + (i % layout.columns).to_double() * layout.column_width
    }
    let at = if layout.columns > 0 {
      y + (i / layout.columns).to_double() * layout.row_height
    } else if self.legend_bottom {
      y
    } else {
      y + i.to_double() * layout.row_height
    }
    let style = layout.styles[i]
    let middle = at + line_middle(label, probe)
    let pen_width = style.paint.width.min(133000.0 / 12700)
    out.push(
      line_path(
        [
          Move(x + legend_gap, middle + 0.5 * 72 / 25.4 - pen_width / 2),
          Line(
            x + legend_gap + marker_line,
            middle + 0.5 * 72 / 25.4 - pen_width / 2,
          ),
        ],
        (style.paint.color, pen_width),
        dash=style.dash,
      ),
    )
    // The native series legend has no marker when only point markers are compiled.
    if style.show_legend_marker {
      { ..style.paint, marker_size: 2.5 * 72 / 25.4, }.marker_at(
        out,
        x + legend_gap + marker_line / 2,
        middle,
        legend=true,
      )
    }
    line_place(out, label, x + 2 * legend_gap + marker_line, at)
    if self.legend_bottom {
      left += label.widths[0] + marker_line + 2 * legend_gap
    }
  }
}
