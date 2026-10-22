///|
fn scatter_markup(
  data : @layout.ChartData,
  workbook_link : String,
) -> String raise @failure.Failure {
  let last = (data.categories.length() + 1).to_string()
  let xs = chart_reference("Sheet1!$A$2:$A$" + last, data.categories, true)
  let out = StringBuilder()
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(data.title)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/><c:scatterChart><c:scatterStyle val=\"marker\"/><c:varyColors val=\"0\"/>"
  for index, series in data.series {
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
    let color = @layout.chart_color(index)
    out <+
      "<c:ser><c:idx val=\"\{index}\"/><c:order val=\"\{index}\"/><c:tx>\{title}</c:tx><c:spPr><a:ln><a:noFill/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:marker><c:xVal>\{xs}</c:xVal><c:yVal>\{ys}</c:yVal><c:smooth val=\"0\"/></c:ser>"
  }
  out <+ "<c:axId val=\"1\"/><c:axId val=\"2\"/></c:scatterChart>"
  for
    (id, position, axis) in [
      (1, "b", data.scatter_axis()),
      (2, "l", data.axis()),
    ] {
    let (low, high, step) = axis
    let title = if id == 1 { chart_title(data.label) } else { "" }
    out <+
      "<c:valAx><c:axId val=\"\{id}\"/><c:scaling><c:orientation val=\"minMax\"/><c:max val=\"\{high}\"/><c:min val=\"\{low}\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\{position}\"/><c:majorGridlines/>\{title}<c:numFmt formatCode=\"General\" sourceLinked=\"0\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\{3-id}\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/><c:majorUnit val=\"\{step}\"/></c:valAx>"
  }
  out <+
    "</c:plotArea>\{legend_markup(data)}<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out.to_string()
}
