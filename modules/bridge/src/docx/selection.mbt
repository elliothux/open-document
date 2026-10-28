///|
fn field_selection(json : Json) -> @model.Selection raise @failure.Failure {
  guard json is { "selection": { "anchor": anchor, "focus": focus, .. }, .. } else {
    @failure.reject("invalid-operation", "Explicit selection is required")
  }
  { anchor: field_position(anchor), focus: field_position(focus), }
}

///|
fn field_position(json : Json) -> @model.Position raise @failure.Failure {
  {
    paragraph: field_int(json, "paragraph"),
    offset: field_int(json, "offset"),
    affinity: field_string(json, "affinity"),
    bidiLevel: if json is Object(fields) && fields.contains("bidiLevel") {
      Some(field_int(json, "bidiLevel"))
    } else {
      None
    },
    frameStart: if json is Object(fields) && fields.contains("frameStart") {
      Some(field_int(json, "frameStart"))
    } else {
      None
    },
  }
}
