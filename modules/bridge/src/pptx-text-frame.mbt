///|
fn pptx_text_frame(change : Json) -> @pptx.ObjectEdit raise @failure.Failure {
  match field_string(change, "action") {
    "textInsets" =>
      @pptx.TextInsets(
        xlsx_number(change, "left"),
        xlsx_number(change, "top"),
        xlsx_number(change, "right"),
        xlsx_number(change, "bottom"),
      )
    "textAnchor" => @pptx.TextAnchor(field_string(change, "anchor"))
    "textWrap" => @pptx.TextWrap(xlsx_boolean(change, "wrap"))
    "textFit" => @pptx.TextFit(field_string(change, "fit"))
    "textUpright" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "upright"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid upright text fields")
      }
      @pptx.TextUpright(xlsx_boolean(change, "upright"))
    }
    "textRotation" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "angle"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text rotation fields")
      }
      @pptx.TextRotation(xlsx_number(change, "angle"))
    }
    "textDirection" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "direction"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text direction fields")
      }
      @pptx.TextDirection(field_string(change, "direction"))
    }
    "textColumns" => {
      guard change is Object(fields) &&
        fields.length() == 4 &&
        fields
        .keys()
        .all(key => ["action", "columns", "gap", "rtl"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text column fields")
      }
      @pptx.TextColumns(
        field_int(change, "columns"),
        xlsx_number(change, "gap"),
        xlsx_boolean(change, "rtl"),
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown text frame action")
  }
}
