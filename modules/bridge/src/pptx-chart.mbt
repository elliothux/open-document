///|
fn pptx_chart_edit(
  change : Json,
  insert : Bool,
) -> @pptx.ObjectEdit raise @failure.Failure {
  let keys = if insert {
    ["action", "kind", "title", "data", "x", "y", "width", "height"]
  } else {
    ["action", "kind", "title", "data"]
  }
  let hole_size = if change is Object(fields) && fields.contains("holeSize") {
    keys.push("holeSize")
    Some(field_int(change, "holeSize"))
  } else {
    None
  }
  let legend = if change is Object(fields) && fields.contains("legend") {
    keys.push("legend")
    Some(field_string(change, "legend"))
  } else {
    None
  }
  guard change is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid chart edit fields")
  }
  let kind = field_string(change, "kind")
  let title = field_string(change, "title")
  let data = field_string(change, "data")
  if insert {
    @pptx.InsertChart(
      kind,
      title,
      data,
      xlsx_number(change, "x"),
      xlsx_number(change, "y"),
      xlsx_number(change, "width"),
      xlsx_number(change, "height"),
      hole_size,
      legend,
    )
  } else if field_string(change, "action") == "fillChart" {
    @pptx.FillChart(kind, title, data, hole_size, legend)
  } else {
    @pptx.ChartData(kind, title, data, hole_size, legend)
  }
}
