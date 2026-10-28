///|
fn pie_point_markup(index : Int32, color : String) -> String {
  "<c:dPt><c:idx val=\"\{index}\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:dPt>"
}

///|
fn pie_markup(
  data : @layout.ChartData,
  workbook_link : String,
) -> String raise @failure.Failure {
  let last = data.categories.length() + 1
  let categories = chart_reference(
    "Sheet1!$A$2:$A$" + last.to_string(),
    data.categories,
    false,
  )
  let out = StringBuilder()
  let kind = if data.kind == "doughnut" { "doughnutChart" } else { "pieChart" }
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(data.title, subtitle=data.label)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/><c:\{kind}><c:varyColors val=\"1\"/>"
  for index, series in data.series {
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
      "<c:ser><c:idx val=\"\{index}\"/><c:order val=\"\{index}\"/><c:tx>\{title}</c:tx><c:spPr><a:solidFill><a:srgbClr val=\"\{@layout.chart_color(0)}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr>"
    if index == 0 || data.kind == "doughnut" {
      for category in 0..<data.categories.length() {
        out.write_string(
          pie_point_markup(category, @layout.chart_color(category)),
        )
      }
    }
    out <+ "<c:cat>\{categories}</c:cat><c:val>\{values}</c:val></c:ser>"
  }
  out <+ "<c:firstSliceAng val=\"0\"/>"
  if data.hole_size is Some(size) {
    out <+ "<c:holeSize val=\"\{size}\"/>"
  }
  out <+
    "</c:\{kind}></c:plotArea>\{legend_markup(data)}<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out.to_string()
}
