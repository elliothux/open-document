///|
fn ChartData::scatter_values(
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
fn ChartData::scatter_axis(
  self : ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let data = {
    ..self,
    series: [{ name: self.label, values: self.scatter_values(), }],
  }
  data.axis()
}

///|
fn ChartData::scatter_markup(
  self : ChartData,
  workbook_link : String,
) -> String raise @failure.Failure {
  let last = (self.categories.length() + 1).to_string()
  let xs = chart_reference("Sheet1!$A$2:$A$" + last, self.categories, true)
  let out = StringBuilder()
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(self.title)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/><c:scatterChart><c:scatterStyle val=\"marker\"/><c:varyColors val=\"0\"/>"
  for index, series in self.series {
    let column = ["B", "C", "D", "E", "F", "G", "H", "I"][index]
    let title = chart_reference(
      "Sheet1!$" + column + "$1",
      [series.name],
      false,
    )
    let ys = chart_reference(
      "Sheet1!$" + column + "$2:$" + column + "$" + last,
      series.values.map(value => value.map(v => v.to_string()).unwrap_or("")),
      true,
    )
    let color = chart_color(index)
    out <+
      "<c:ser><c:idx val=\"\{index}\"/><c:order val=\"\{index}\"/><c:tx>\{title}</c:tx><c:spPr><a:ln><a:noFill/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:marker><c:xVal>\{xs}</c:xVal><c:yVal>\{ys}</c:yVal><c:smooth val=\"0\"/></c:ser>"
  }
  out <+ "<c:axId val=\"1\"/><c:axId val=\"2\"/></c:scatterChart>"
  for
    (id, position, axis) in [
      (1, "b", self.scatter_axis()),
      (2, "l", self.axis()),
    ] {
    let (low, high, step) = axis
    let title = if id == 1 { chart_title(self.label) } else { "" }
    out <+
      "<c:valAx><c:axId val=\"\{id}\"/><c:scaling><c:orientation val=\"minMax\"/><c:max val=\"\{high}\"/><c:min val=\"\{low}\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\{position}\"/><c:majorGridlines/>\{title}<c:numFmt formatCode=\"General\" sourceLinked=\"0\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\{3-id}\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/><c:majorUnit val=\"\{step}\"/></c:valAx>"
  }
  out <+
    "</c:plotArea>\{self.legend_markup()}<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out.to_string()
}

///|
fn ChartData::paint_scatter(
  self : ChartData,
  left : Double,
  top : Double,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let (low, high, step) = self.scatter_axis()
  let (y_low, y_high, _) = self.axis()
  let out : Array[@layout.PositionedPrimitive] = []
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
            chart_color(index),
          ),
        )
      }
    }
  }
  out
}
