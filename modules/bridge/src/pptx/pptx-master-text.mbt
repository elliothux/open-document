///|
priv struct MasterTextStyleRequest {
  kind : String
  level : @common.RequestInt
  format : Json
} derive(@json.FromJson)

///|
fn pptx_master_text_style(
  action : String,
  change : Json,
) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) && fields.length() == 4 else {
    @failure.reject("invalid-operation", "Invalid master text style fields")
  }
  let request : MasterTextStyleRequest = @common.request(change)
  let level = request.level.value
  let format = request.format
  guard level <= 8 else {
    @failure.reject("invalid-operation", "Invalid master text style level")
  }
  if action == "masterParagraphStyle" {
    if format is Null {
      return @model.MasterParagraphStyle(request.kind, level, None, None)
    }
    guard format is Object(properties) &&
      !properties.is_empty() &&
      !properties.contains("level") else {
      @failure.reject(
        "invalid-operation", "Invalid master paragraph properties",
      )
    }
    let rest = properties.copy()
    let alignment = rest.get("alignment").map(@common.request)
    ignore(rest.remove("alignment"))
    return @model.MasterParagraphStyle(
      request.kind,
      level,
      if rest.is_empty() {
        None
      } else {
        Some(pptx_paragraph_format(Json::object(rest)))
      },
      alignment,
    )
  }
  @model.MasterTextStyle(
    request.kind,
    level,
    if format is Null {
      None
    } else {
      let format : TextFormatInput = @common.request(format)
      Some(format.value)
    },
  )
}
