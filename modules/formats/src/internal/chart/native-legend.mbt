///|
struct NativeLegend {
  text : @layout.TextStyle
  fill : String
  pen : (String, Double)
  join : Int32
  position : (Double, Double)?
}

///|
fn native_legend_position(
  position : (Double, Double)?,
  frame : (Double, Double),
  size : (Double, Double),
  fallback : (Double, Double),
) -> (Double, Double) {
  // ONLYOFFICE ChartSpace.calculatePosByLayout keeps manual edge positions inside the frame.
  position
  .map(p => {
    (
      (p.0 * frame.0).min(frame.0 - size.0).max(0),
      (p.1 * frame.1).min(frame.1 - size.1).max(0),
    )
  })
  .unwrap_or(fallback)
}

///|
fn native_legend(
  source : Ref,
  side~ : String = "r",
  round_join~ : Bool = false,
) -> NativeLegend raise @failure.Failure {
  line_fields(source, ["legendPos", "layout", "spPr", "txPr", "overlay"])
  if source.child("overlay", uri=chart_uri) is Some(overlay) {
    native_flag(overlay, "0")
  }
  native_flag(chart_child(source, "legendPos"), side)
  let properties = chart_child(source, "spPr")
  let (fill, pen) = if side == "b" {
    let (fill, pen, dash) = line_paint_box(properties)
    guard dash.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Native legend dash requires support",
      )
    }
    (fill, pen)
  } else {
    line_box(properties, round_join~)
  }
  let join = if properties.child("ln").bind(line => line.child("round"))
    is Some(_) {
    1
  } else {
    0
  }
  let layout = chart_child(source, "layout")
  line_fields(layout, ["manualLayout"])
  let position = layout
    .child("manualLayout", uri=chart_uri)
    .map(manual => {
      line_fields(manual, ["xMode", "yMode", "x", "y"])
      native_flag(chart_child(manual, "xMode"), "edge")
      native_flag(chart_child(manual, "yMode"), "edge")
      (
        line_real(
          chart_child(manual, "x").node.attribute("val").unwrap_or(""),
          0,
          1,
        ),
        line_real(
          chart_child(manual, "y").node.attribute("val").unwrap_or(""),
          0,
          1,
        ),
      )
    })
  { text: line_text(chart_child(source, "txPr")), fill, pen, join, position, }
}
