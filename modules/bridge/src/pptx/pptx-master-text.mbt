///|
fn pptx_master_text_style(
  change : Json,
) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 4 &&
    fields.get("format") is Some(format) else {
    @failure.reject("invalid-operation", "Invalid master text style fields")
  }
  let level = field_number(change, "level")
  guard level >= 0 && level <= 8 && level.round() == level else {
    @failure.reject("invalid-operation", "Invalid master text style level")
  }
  if field_string(change, "action") == "masterParagraphStyle" {
    if format is Null {
      return @model.MasterParagraphStyle(
        field_string(change, "kind"),
        level.to_int(),
        None,
        None,
      )
    }
    guard format is Object(properties) &&
      !properties.is_empty() &&
      !properties.contains("level") else {
      @failure.reject(
        "invalid-operation", "Invalid master paragraph properties",
      )
    }
    let alignment = properties
      .get("alignment")
      .map(_ => field_string(format, "alignment"))
    let rest = properties.copy()
    ignore(rest.remove("alignment"))
    return @model.MasterParagraphStyle(
      field_string(change, "kind"),
      level.to_int(),
      if rest.is_empty() {
        None
      } else {
        Some(pptx_paragraph_format(Json::object(rest)))
      },
      alignment,
    )
  }
  @model.MasterTextStyle(
    field_string(change, "kind"),
    level.to_int(),
    if format is Null {
      None
    } else {
      Some(pptx_text_format(format))
    },
  )
}
