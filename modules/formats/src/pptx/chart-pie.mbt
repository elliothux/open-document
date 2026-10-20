///|
fn ChartData::pie_markup(
  self : ChartData,
  workbook_link : String,
) -> String raise @failure.Failure {
  let last = self.categories.length() + 1
  let categories = chart_reference(
    "Sheet1!$A$2:$A$" + last.to_string(),
    self.categories,
    false,
  )
  let out = StringBuilder()
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(self.title, subtitle=self.label)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/><c:pieChart><c:varyColors val=\"1\"/>"
  for index, series in self.series {
    let column = ["B", "C", "D", "E", "F", "G", "H", "I"][index]
    let title = chart_reference(
      "Sheet1!$" + column + "$1",
      [series.name],
      false,
    )
    let values = chart_reference(
      "Sheet1!$" + column + "$2:$" + column + "$" + last.to_string(),
      series.values.map(v => v.map(v => v.to_string()).unwrap_or("")),
      true,
    )
    out <+
      "<c:ser><c:idx val=\"\{index}\"/><c:order val=\"\{index}\"/><c:tx>\{title}</c:tx><c:spPr><a:solidFill><a:srgbClr val=\"\{chart_color(0)}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr>"
    if index == 0 {
      for category in 0..<self.categories.length() {
        out <+
          "<c:dPt><c:idx val=\"\{category}\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{chart_color(category)}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:dPt>"
      }
    }
    out <+ "<c:cat>\{categories}</c:cat><c:val>\{values}</c:val></c:ser>"
  }
  out <+
    "<c:firstSliceAng val=\"0\"/></c:pieChart></c:plotArea><c:legend><c:legendPos val=\"r\"/><c:overlay val=\"0\"/></c:legend><c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out.to_string()
}

///|
fn ChartData::pie_slices(self : ChartData) -> Array[(Double, Double)] {
  let values = self.series[0].values.map(v => v.unwrap_or(0).abs())
  let maximum = values.fold(init=0.0, (a, b) => a.max(b))
  if maximum == 0 {
    return values.map(_ => (0.0, 0.0))
  }
  // Scale before summing so finite source values cannot overflow the total.
  let weights = values.map(v => v / maximum)
  let total = weights.fold(init=0.0, (a, b) => a + b)
  let slices : Array[(Double, Double)] = []
  let mut used = 0.0
  for weight in weights {
    let start = used / total
    used += weight
    slices.push((start, used / total))
  }
  slices
}

///|
fn chart_sector(
  start : Double,
  end : Double,
  x : Double,
  y : Double,
  radius : Double,
) -> Array[@layout.PathSegment] {
  let angle = start * 2 * @math.PI - @math.PI / 2
  let sweep = (end - start) * 2 * @math.PI
  let count = (sweep / (@math.PI / 2)).ceil().to_int().max(1)
  let path : Array[@layout.PathSegment] = [
    Move(x, y),
    Line(x + radius * @math.cos(angle), y + radius * @math.sin(angle)),
  ]
  for i in 0..<count {
    let a = angle + sweep * i.to_double() / count.to_double()
    let b = angle + sweep * (i + 1).to_double() / count.to_double()
    let k = 4.0 / 3 * @math.tan((b - a) / 4)
    let x0 = x + radius * @math.cos(a)
    let y0 = y + radius * @math.sin(a)
    let x1 = x + radius * @math.cos(b)
    let y1 = y + radius * @math.sin(b)
    path.push(
      Cubic(
        x0 - k * radius * @math.sin(a),
        y0 + k * radius * @math.cos(a),
        x1 + k * radius * @math.sin(b),
        y1 - k * radius * @math.cos(b),
        x1,
        y1,
      ),
    )
  }
  path.push(Close)
  path
}

///|
fn DrawingChart::paint_pie(
  self : DrawingChart,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let data = self.data
  let out = chart_label(
    data.label,
    8,
    26,
    width - 16,
    18,
    12,
    true,
    probe,
    profile,
  )
  let area = width * 0.65
  let radius = (area - 20).min(height - 62) / 2
  let x = area / 2
  let y = 48.0 + (height - 62) / 2
  for index, (start, end) in data.pie_slices() {
    if end > start {
      out.push(
        Path(
          chart_sector(start, end, x, y, radius),
          chart_color(index),
          "",
          0,
          { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 8, },
        ),
      )
    }
  }
  let rows = ((height - 58) / 16).floor().to_int().max(1)
  let visible = if data.categories.length() > rows {
    rows - 1
  } else {
    data.categories.length()
  }
  for i in 0..<visible {
    let y = 48.0 + i.to_double() * 16
    out.push(
      Rectangle({
        x: area + 4,
        y: y + 3,
        width: 8,
        height: 8,
        color: chart_color(i),
      }),
    )
    out.append(
      chart_label(
        data.categories[i],
        area + 16,
        y,
        width - area - 20,
        16,
        10,
        false,
        probe,
        profile,
      ),
    )
  }
  if visible < data.categories.length() {
    out.append(
      chart_label(
        "... (+\{data.categories.length() - visible})",
        area + 4,
        48.0 + visible.to_double() * 16,
        width - area - 8,
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
