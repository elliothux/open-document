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
  let kind = if self.kind == "doughnut" { "doughnutChart" } else { "pieChart" }
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(self.title, subtitle=self.label)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/><c:\{kind}><c:varyColors val=\"1\"/>"
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
    if index == 0 || self.kind == "doughnut" {
      for category in 0..<self.categories.length() {
        out <+
          "<c:dPt><c:idx val=\"\{category}\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{chart_color(category)}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:dPt>"
      }
    }
    out <+ "<c:cat>\{categories}</c:cat><c:val>\{values}</c:val></c:ser>"
  }
  out <+ "<c:firstSliceAng val=\"0\"/>"
  if self.hole_size is Some(size) {
    out <+ "<c:holeSize val=\"\{size}\"/>"
  }
  out <+
    "</c:\{kind}></c:plotArea>\{self.legend_markup()}<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out.to_string()
}

///|
fn ChartData::pie_slices(
  self : ChartData,
  series~ : Int = 0,
) -> Array[(Double, Double)] {
  let values = self.series[series].values.map(v => v.unwrap_or(0).abs())
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
  inner~ : Double = 0,
) -> Array[@layout.PathSegment] {
  let angle = start * 2 * @math.PI - @math.PI / 2
  let sweep = (end - start) * 2 * @math.PI
  let count = (sweep / (@math.PI / 2)).ceil().to_int().max(1)
  let path : Array[@layout.PathSegment] = if inner == 0 {
    [
      Move(x, y),
      Line(x + radius * @math.cos(angle), y + radius * @math.sin(angle)),
    ]
  } else {
    [Move(x + radius * @math.cos(angle), y + radius * @math.sin(angle))]
  }
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
  if inner > 0 {
    path.push(
      Line(
        x + inner * @math.cos(angle + sweep),
        y + inner * @math.sin(angle + sweep),
      ),
    )
    for i in 0..<count {
      let a = angle + sweep * (1 - i.to_double() / count.to_double())
      let b = angle + sweep * (1 - (i + 1).to_double() / count.to_double())
      let k = 4.0 / 3 * @math.tan((b - a) / 4)
      let x0 = x + inner * @math.cos(a)
      let y0 = y + inner * @math.sin(a)
      let x1 = x + inner * @math.cos(b)
      let y1 = y + inner * @math.sin(b)
      path.push(
        Cubic(
          x0 - k * inner * @math.sin(a),
          y0 + k * inner * @math.cos(a),
          x1 + k * inner * @math.sin(b),
          y1 - k * inner * @math.cos(b),
          x1,
          y1,
        ),
      )
    }
  }
  path.push(Close)
  path
}

///|
fn DrawingChart::paint_pie(
  self : DrawingChart,
  width : Double,
  height : Double,
) -> Array[@layout.PositionedPrimitive] {
  let data = self.data
  let out : Array[@layout.PositionedPrimitive] = []
  let area = width
  let radius = (area - 20).min(height - 62) / 2
  let x = area / 2
  let y = 48.0 + (height - 62) / 2
  let rings = if data.kind == "doughnut" { data.series.length() } else { 1 }
  let hole = radius * data.hole_size.unwrap_or(0).to_double() / 100
  let thickness = (radius - hole) / rings.to_double()
  let mut ring = 0
  for series in 0..<rings {
    for index, (start, end) in data.pie_slices(series~) {
      if end > start {
        out.push(
          Path(
            chart_sector(
              start,
              end,
              x,
              y,
              hole + thickness * (ring + 1).to_double(),
              inner=hole + thickness * ring.to_double(),
            ),
            chart_color(index),
            "",
            0,
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
      }
    }
    if data.series[series].values.any(value => value is Some(_)) {
      ring += 1
    }
  }
  out
}
