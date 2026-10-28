///|
fn pptx_text_frame(change : Json) -> @model.ObjectEdit raise @failure.Failure {
  match field_string(change, "action") {
    "textInsets" =>
      @model.TextInsets(
        field_number(change, "left"),
        field_number(change, "top"),
        field_number(change, "right"),
        field_number(change, "bottom"),
      )
    "textAnchor" => @model.TextAnchor(field_string(change, "anchor"))
    "textWrap" => @model.TextWrap(field_boolean(change, "wrap"))
    "textFit" => @model.TextFit(field_string(change, "fit"))
    "textUpright" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "upright"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid upright text fields")
      }
      @model.TextUpright(field_boolean(change, "upright"))
    }
    "textRotation" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "angle"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text rotation fields")
      }
      @model.TextRotation(field_number(change, "angle"))
    }
    "textDirection" => {
      guard change is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["action", "direction"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text direction fields")
      }
      @model.TextDirection(field_string(change, "direction"))
    }
    "textColumns" => {
      guard change is Object(fields) &&
        fields.length() == 4 &&
        fields
        .keys()
        .all(key => ["action", "columns", "gap", "rtl"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid text column fields")
      }
      @model.TextColumns(
        field_int(change, "columns"),
        field_number(change, "gap"),
        field_boolean(change, "rtl"),
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown text frame action")
  }
}
