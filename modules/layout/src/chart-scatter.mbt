///|
pub fn ChartData::scatter_values(
  self : ChartData,
) -> Array[Double?] raise @failure.Failure {
  self.categories.map(text => {
    if text.is_empty() {
      return None
    }
    let value = @string.parse_double(text) catch {
      _ =>
        @failure.reject(
          "invalid-chart", "Scatter X values require finite numbers or blanks",
        )
    }
    guard !value.is_nan() && !value.is_inf() else {
      @failure.reject(
        "invalid-chart", "Scatter X values require finite numbers or blanks",
      )
    }
    Some(value)
  })
}

///|
pub fn ChartData::scatter_axis(
  self : ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let data = {
    ..self,
    series: [{ name: self.label, values: self.scatter_values(), }],
  }
  data.axis()
}

///|
fn ChartData::paint_scatter(
  self : ChartData,
  left : Double,
  top : Double,
  width : Double,
  height : Double,
  probe : TextProbe,
  profile : Map[String, String],
  colors : Array[String],
) -> Array[PositionedPrimitive] raise @failure.Failure {
  let (low, high, step) = self.scatter_axis()
  let (y_low, y_high, _) = self.axis()
  let out : Array[PositionedPrimitive] = []
  let ticks = ((high - low) / step).round().to_int()
  guard ticks >= 1 && ticks <= 20 else {
    @failure.reject("limit-exceeded", "Chart tick count exceeds limits")
  }
  for i in 0..<=ticks {
    let value = low + step * i.to_double()
    let x = left + width * ((value - low) / (high - low))
    out.push(
      Path([Move(x, top), Line(x, top + height)], "", "d9d9d9", 0.5, {
        fillAlpha: 1,
        strokeAlpha: 1,
        dash: [],
        cap: 0,
        join: 0,
        miter: 8,
      }),
    )
    out.append(
      chart_label(
        value.to_string(),
        (x - 22).max(0),
        top + height + 4,
        (x + 22).min(left + width + 12) - (x - 22).max(0),
        16,
        9,
        true,
        probe,
        profile,
      ),
    )
  }
  let xs = self.scatter_values()
  for index, series in self.series {
    for row, value in series.values {
      if (xs[row], value) is (Some(x), Some(y)) {
        out.append(
          chart_marker(
            left + width * ((x - low) / (high - low)),
            top + height * (1 - (y - y_low) / (y_high - y_low)),
            chart_paint_color(colors, index),
          ),
        )
      }
    }
  }
  out
}
