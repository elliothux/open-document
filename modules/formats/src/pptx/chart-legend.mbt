///|
fn ChartData::legend_markup(self : ChartData) -> String {
  if self.legend == "none" {
    return ""
  }
  let position = match self.legend {
    "top" => "t"
    "left" => "l"
    "right" => "r"
    _ => "b"
  }
  "<c:legend><c:legendPos val=\"\{position}\"/><c:overlay val=\"0\"/></c:legend>"
}

///|
priv struct ChartLegendLayout {
  plot : @layout.Border
  entries : Array[(String, Int, @layout.Border)]
}

///|
fn ChartData::legend_layout(
  self : ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> ChartLegendLayout raise @failure.Failure {
  let plot : @layout.Border = { x: 0, y: 0, width, height, }
  if self.legend == "none" {
    return { plot, entries: [], }
  }
  let pie = ["pie", "doughnut"].contains(self.kind)
  let mut labels = (if pie {
    self.categories
  } else {
    self.series.map(series => series.name)
  }).mapi((index, name) => (name, index))
  let side = ["left", "right"].contains(self.legend)
  if side && stacked_chart(self.kind) {
    labels = Array::makei(labels.length(), index => {
      labels[labels.length() - 1 - index]
    })
  }
  let header = if pie { 48.0 } else { 30.0 }
  let (columns, rows, cell_width, legend_height) = if side {
    (
      1,
      ((height - header - 10) / 16).floor().to_int().max(1),
      (width * 0.35).min(width - 136),
      0.0,
    )
  } else {
    let natural = labels.fold(init=0.0, (largest, item) => {
      if item.0.is_empty() {
        return largest.max(20)
      }
      let block = probe.text_block(
        item.0,
        @layout.TextStyle::new("Arial", 10, "222222"),
        profile,
        width - 16,
        false,
      )
      largest.max(block.widths[0] + 20)
    })
    let columns = ((width - 16) / natural.max(20))
      .floor()
      .to_int()
      .max(1)
      .min(labels.length())
    let maximum = ((height * 0.3).min(height - 128) - 6) / 16
    let rows = ((labels.length() + columns - 1) / columns).min(
      maximum.floor().to_int().max(1),
    )
    (
      columns,
      rows,
      (width - 16) / columns.to_double(),
      rows.to_double() * 16 + 6,
    )
  }
  let capacity = rows * columns
  let visible = if labels.length() > capacity {
    capacity - 1
  } else {
    labels.length()
  }
  let displayed = labels[:visible].to_owned()
  if visible < labels.length() {
    displayed.push(("... (+\{labels.length()-visible})", -1))
  }
  let entries = displayed.mapi((index, item) => {
    let row = index / columns
    let column = index % columns
    let (x, y) = if side {
      (
        if self.legend == "left" {
          4.0
        } else {
          width - cell_width + 4
        },
        header +
        (height - header - 10 - displayed.length().to_double() * 16) / 2 +
        row.to_double() * 16,
      )
    } else {
      let on_row = columns.min(displayed.length() - row * columns)
      (
        (width - cell_width * on_row.to_double()) / 2 +
        column.to_double() * cell_width,
        (if self.legend == "top" { header } else { height - legend_height }) +
        1 +
        row.to_double() * 16,
      )
    }
    let rect : @layout.Border = { x, y, width: cell_width - 8, height: 16, }
    (item.0, item.1, rect)
  })
  let plot : @layout.Border = if side {
    {
      x: if self.legend == "left" {
        cell_width
      } else {
        0
      },
      y: 0,
      width: width - cell_width,
      height,
    }
  } else {
    {
      x: 0,
      y: if self.legend == "top" {
        legend_height
      } else {
        0
      },
      width,
      height: height - legend_height,
    }
  }
  { plot, entries, }
}

///|
fn ChartData::paint_legend(
  self : ChartData,
  entries : Array[(String, Int, @layout.Border)],
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let out : Array[@layout.PositionedPrimitive] = []
  for (text, index, rect) in entries {
    if index >= 0 {
      let color = chart_color(index)
      if self.kind == "scatter" {
        out.append(chart_marker(rect.x + 4, rect.y + 7, color))
      } else if ["line", "radar"].contains(self.kind) {
        out.push(
          Path(
            [Move(rect.x, rect.y + 7), Line(rect.x + 8, rect.y + 7)],
            "",
            color,
            1.5,
            {
              fillAlpha: 1,
              strokeAlpha: 1,
              dash: [],
              cap: 0,
              join: 0,
              miter: 8,
            },
          ),
        )
        out.append(chart_marker(rect.x + 4, rect.y + 7, color))
      } else {
        out.push(
          Rectangle({ x: rect.x, y: rect.y + 3, width: 8, height: 8, color, }),
        )
      }
    }
    let marker = if index >= 0 { 12.0 } else { 0.0 }
    out.append(
      chart_label(
        text,
        rect.x + marker,
        rect.y,
        rect.width - marker,
        16,
        10,
        false,
        probe,
        profile,
      ),
    )
  }
  out
}

///|
fn DrawingChart::paint(
  self : DrawingChart,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  guard width >= 180 && height >= 150 else {
    @failure.reject(
      "layout-overflow", "Chart frame requires at least 180 x 150 points",
    )
  }
  let data = self.data
  let layout = data.legend_layout(width, height, probe, profile)
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: "ffffff", }),
    Stroke({ x: 0, y: 0, width, height, }, "d9d9d9", 0.5),
  ]
  out.append(
    chart_label(data.title, 8, 6, width - 16, 20, 12, true, probe, profile),
  )
  if ["pie", "doughnut"].contains(data.kind) {
    out.append(
      chart_label(data.label, 8, 26, width - 16, 18, 12, true, probe, profile),
    )
  }
  out.push(Clip(layout.plot))
  out.push(
    Transform({ a: 1, b: 0, c: 0, d: 1, e: layout.plot.x, f: layout.plot.y, }),
  )
  out.append(
    self.paint_plot(layout.plot.width, layout.plot.height, probe, profile),
  )
  out.push(Restore)
  out.push(Restore)
  out.append(data.paint_legend(layout.entries, probe, profile))
  out
}
