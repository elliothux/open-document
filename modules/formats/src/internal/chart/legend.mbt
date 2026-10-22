///|
fn legend_markup(data : @layout.ChartData) -> String {
  if data.legend == "none" {
    return ""
  }
  let position = match data.legend {
    "top" => "t"
    "left" => "l"
    "right" => "r"
    _ => "b"
  }
  "<c:legend><c:legendPos val=\"\{position}\"/><c:overlay val=\"0\"/></c:legend>"
}
