///|
fn text_watermark_value(
  request : Json,
) -> @model.Watermark? raise @failure.Failure {
  guard request is { "value": value, .. } else {
    @failure.reject("invalid-operation", "Watermark value is required")
  }
  if value is Null {
    return None
  }
  if value is { "kind": "picture", "image": image, .. } {
    guard value is Object(fields) &&
      fields.length() == 5 &&
      fields
      .keys()
      .all(key => ["kind", "image", "width", "height", "opacity"].contains(key)) else {
      @failure.reject("invalid-operation", "Invalid picture watermark fields")
    }
    let image = match image {
      String(key) => @model.WatermarkImage::Resource(key)
      Object(fields) if fields.length() == 1 && fields.contains("bytes") =>
        @model.WatermarkImage::Data(input_bytes(image, 4194304))
      _ => @failure.reject("invalid-operation", "Invalid watermark image")
    }
    return Some(
      @model.Watermark::Picture(
        image,
        field_number(value, "width"),
        field_number(value, "height"),
        field_number(value, "opacity"),
      ),
    )
  }
  guard value is { "kind": "text", "value": text, .. } &&
    value is Object(outer) &&
    outer.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid watermark kind")
  }
  let value = text
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
  Some(
    @model.Watermark::Text({
      text: field_string(value, "text"),
      font: field_string(value, "font"),
      size: field_number(value, "size"),
      color: field_string(value, "color"),
      opacity: field_number(value, "opacity"),
      diagonal: field_boolean(value, "diagonal"),
      bold: field_boolean(value, "bold"),
      italic: field_boolean(value, "italic"),
    }),
  )
}
