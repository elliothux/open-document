///|
fn text_watermark_value(
  request : Json,
) -> @docx.TextWatermark? raise @failure.Failure {
  guard request is { "value": value, .. } else {
    @failure.reject("invalid-operation", "Watermark value is required")
  }
  if value is Null {
    return None
  }
  guard value is Object(fields) &&
    fields.length() == 8 &&
    fields
    .keys()
    .all(key => {
      ["text", "font", "size", "color", "opacity", "diagonal", "bold", "italic"].contains(
        key,
      )
    }) else {
    @failure.reject("invalid-operation", "Invalid watermark fields")
  }
  Some({
    text: field_string(value, "text"),
    font: field_string(value, "font"),
    size: xlsx_number(value, "size"),
    color: field_string(value, "color"),
    opacity: xlsx_number(value, "opacity"),
    diagonal: xlsx_boolean(value, "diagonal"),
    bold: xlsx_boolean(value, "bold"),
    italic: xlsx_boolean(value, "italic"),
  })
}
