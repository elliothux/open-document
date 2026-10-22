///|
fn Foundation::chart_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  if operation == "docxCharts" {
    return session.charts(revision)
  }
  guard request is { "chart": chart, .. } && chart is Object(fields) else {
    @failure.reject("invalid-operation", "Chart settings are required")
  }
  let action = field_string(chart, "action")
  guard ["insert", "update", "delete", "resize", "position"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown chart action")
  }
  let keys = ["action"]
  if action != "insert" {
    keys.push("id")
  }
  let content = action == "insert" || action == "update"
  if content {
    keys.append(["kind", "title", "data", "width", "height"])
    for key in ["holeSize", "legend"] {
      if fields.contains(key) {
        keys.push(key)
      }
    }
  }
  if action == "resize" {
    keys.append(["width", "height"])
  }
  if action == "position" {
    keys.push("anchor")
    if fields.contains("target") {
      keys.push("target")
    }
  }
  guard fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Unknown chart settings")
  }
  let remove = action == "delete"
  let result = if action == "position" {
    session.set_drawing_anchor(
      revision,
      field_int(chart, "id"),
      drawing_anchor(chart),
      target?=fields.get("target").map(field_position),
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
  } else {
    session.edit_chart(
      revision,
      action,
      if action == "insert" {
        -1
      } else {
        field_int(chart, "id")
      },
      if !content {
        ""
      } else {
        field_string(chart, "kind")
      },
      if !content {
        ""
      } else {
        field_string(chart, "title")
      },
      if !content {
        ""
      } else {
        field_string(chart, "data")
      },
      if remove {
        0
      } else {
        xlsx_number(chart, "width")
      },
      if remove {
        0
      } else {
        xlsx_number(chart, "height")
      },
      hole_size=if fields.contains("holeSize") {
        Some(field_int(chart, "holeSize"))
      } else {
        None
      },
      legend=if fields.contains("legend") {
        Some(field_string(chart, "legend"))
      } else {
        None
      },
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
