///|
priv struct PictureWatermarkRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
  opacity : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct TextWatermarkRequest {
  text : String
  font : String
  size : @common.RequestNumber
  color : String
  opacity : @common.RequestNumber
  diagonal : Bool
  bold : Bool
  italic : Bool
} derive(@json.FromJson)

///|
fn watermark_value(value : Json) -> @model.Watermark? raise @failure.Failure {
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
      { "bytes": String(bytes), .. } as input if input is Object(fields) &&
        fields.length() == 1 =>
        @model.WatermarkImage::Data(
          @common.byte_input(bytes, @model.ImageInputBytes),
        )
      _ => @failure.reject("invalid-operation", "Invalid watermark image")
    }
    let picture : PictureWatermarkRequest = @common.request(value)
    return Some(
      @model.Watermark::Picture(
        image,
        picture.width.value,
        picture.height.value,
        picture.opacity.value,
      ),
    )
  }
  guard value is { "kind": "text", "value": text, .. } &&
    value is Object(outer) &&
    outer.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid watermark kind")
  }
  let value = text
  guard value is Object(fields) && fields.length() == 8 else {
    @failure.reject("invalid-operation", "Invalid watermark fields")
  }
  let text : TextWatermarkRequest = @common.request(value)
  Some(
    @model.Watermark::Text({
      text: text.text,
      font: text.font,
      size: text.size.value,
      color: text.color,
      opacity: text.opacity.value,
      diagonal: text.diagonal,
      bold: text.bold,
      italic: text.italic,
    }),
  )
}
