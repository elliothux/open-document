///|
fn pptx_show_settings(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is { "value": Object(fields) as value, .. } &&
    fields.length() == 4 &&
    fields
    .keys()
    .all(key => ["slides", "timings", "animations", "loop"].contains(key)) &&
    value is { "slides": Object(items) as slides, .. } else {
    @failure.reject("invalid-operation", "Invalid show settings fields")
  }
  let kind = field_string(slides, "kind")
  let allowed = match kind {
    "all" => ["kind"]
    "range" => ["kind", "first", "last"]
    "custom" => ["kind", "id"]
    _ => @failure.reject("invalid-operation", "Unknown show selection")
  }
  guard items.length() == allowed.length() &&
    items.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid show selection fields")
  }
  @model.Settings({
    slides: match kind {
      "all" => @model.ShowAll
      "range" =>
        @model.ShowRange(field_int(slides, "first"), field_int(slides, "last"))
      _ => @model.ShowCustom(field_string(slides, "id"))
    },
    timings: field_boolean(value, "timings"),
    animations: field_boolean(value, "animations"),
    cycling: field_boolean(value, "loop"),
  })
}
