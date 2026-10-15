///|
fn page_setup_format(
  request : Json,
) -> @layout.PageSetup raise @failure.Failure {
  guard request is { "page": Object(fields), .. } &&
    (fields.length() == 6 || fields.length() == 7) &&
    fields
    .keys()
    .all(key => {
      ["width", "height", "top", "right", "bottom", "left", "orientation"].contains(
        key,
      )
    }) else {
    @failure.reject("invalid-operation", "Invalid page setup fields")
  }
  fn number(
    fields : Map[String, Json],
    name : String,
  ) -> Double raise @failure.Failure {
    guard fields.get(name) is Some(Number(value, ..)) else {
      @failure.reject("invalid-operation", "Invalid page setup number")
    }
    value
  }
  {
    width: number(fields, "width"),
    height: number(fields, "height"),
    top: number(fields, "top"),
    right: number(fields, "right"),
    bottom: number(fields, "bottom"),
    left: number(fields, "left"),
  }
}

///|
fn page_orientation(request : Json) -> String? raise @failure.Failure {
  if request is { "page": Object(fields) as page, .. } &&
    fields.contains("orientation") {
    Some(field_string(page, "orientation"))
  } else {
    None
  }
}
