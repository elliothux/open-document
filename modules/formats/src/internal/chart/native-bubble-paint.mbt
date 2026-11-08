///|
fn NativeBubble::paint(
  self : NativeBubble,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
  after_bar3d : Bool,
  print : Bool,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  guard source.kind == "scatter" &&
    width >= 180 &&
    width <= 14400 &&
    height >= 150 &&
    height <= 14400 &&
    !width.is_nan() &&
    !height.is_nan() &&
    self.sizes.length() == source.series.length() &&
    self.sizes
    .mapi((i, sizes) => {
      sizes.length() == source.series[i].values.length() &&
      sizes.length() == source.categories.length() &&
      sizes.all(value => {
        value.map(n => !n.is_nan() && !n.is_inf()).unwrap_or(true)
      })
    })
    .all(value => value) else {
    @failure.reject(
      "layout-overflow", "Native bubble chart requires a bounded aligned frame",
    )
  }
  let axis = fn(
    text : @layout.TextStyle,
    pen : (String, Double),
    grid : (String, Double),
    ticks : (String?, String?),
  ) -> NativeLineAxis {
    {
      text: circular_text_style(text),
      pen,
      major: grid,
      minor: ("", 0),
      major_tick: ticks.0.unwrap_or("out"),
      minor_tick: ticks.1.unwrap_or("none"),
      minimum: None,
      maximum: None,
      title: None,
    }
  }
  // The primary importer converts bubbles to unconnected scatter markers and retains X/Y only for display.
  let series = self.series.map(style => {
    let marker = [
        "diamond", "square", "triangle", "x", "star", "circle", "plus", "dot", "dash",
      ][(style.idx % 9).to_int()]
    let paint : NativeLineSeries = {
      color: "",
      width: 2.25,
      marker,
      marker_size: 7.0 / 2.69 * 72 / 25.4,
      marker_fill: if ["x", "star", "plus"].contains(marker) {
        ""
      } else {
        style.marker_pen.0
      },
      marker_pen: Some(style.marker_pen),
    }
    let points : Map[Int32, NativeLineSeries] = Map([])
    for point in style.styled_points {
      points[point] = {
        ..paint,
        marker_fill: style.fill,
        marker_pen: Some(style.pen),
      }
    }
    NativeLineCurve::{
      idx: style.idx,
      paint,
      show_legend_marker: true,
      plot_markers: true,
      axis: 0,
      smooth: false,
      dash: [],
      labels: None,
      trend: None,
      points,
      column: None,
    }
  })
  let legend = self.legend
  let display : NativeLine = {
    frame_fill: self.frame_fill,
    frame_pen: self.frame_pen,
    frame_default: false,
    frame_dash: [],
    series,
    category: axis(self.x_text, self.x_pen, ("", 0), self.x_ticks),
    secondary_x: None,
    axes: [axis(self.y_text, self.y_pen, self.grid_pen, self.y_ticks)],
    plot: None,
    title: None,
    plot_fill: self.plot_fill,
    plot_pen: self.plot_pen,
    legend_text: circular_text_style(
      legend.map(value => value.text).unwrap_or(self.x_text),
    ),
    legend_fill: legend.map(value => value.fill).unwrap_or(""),
    legend_pen: legend.map(value => value.pen).unwrap_or(("", 0)),
    legend_position: legend.bind(value => value.position),
    legend_bottom: false,
    point_legend: false,
    numeric_categories: true,
  }
  let painted = display.paint(
    source, width, height, probe, profile, visible, after_bar3d, print,
  )
  if print {
    painted
  } else {
    painted
    .map(primitive => {
      match primitive {
        @layout.Path(path, "", color, width, _) if !color.is_empty() &&
          width > 0 &&
          path.length() % 2 == 0 &&
          Array::makei(path.length() / 2, i => {
            path[i * 2] is Move(x, y) &&
            path[i * 2 + 1] is Line(right, bottom) &&
            (x == right || y == bottom)
          }).all(value => value) =>
          Array::makei(path.length() / 2, i => {
            guard path[i * 2] is Move(x, y) &&
              path[i * 2 + 1] is Line(right, bottom) else {
              abort("Validated numeric axis segment")
            }
            @layout.FractionalScreenStroke(
              {
                x: x.min(right),
                y: y.min(bottom),
                width: (right - x).abs(),
                height: (bottom - y).abs(),
              },
              color,
              width,
            )
          })
        @layout.Stroke(rect, color, width) =>
          [@layout.FractionalScreenStroke(rect, color, width)]
        _ => [primitive]
      }
    })
    .flatten()
  }
}
