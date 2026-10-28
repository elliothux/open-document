///|
fn xlsx_value(content : Json) -> @model.Value raise @failure.Failure {
  guard content is Object(fields) &&
    fields.length() == 2 &&
    fields.keys().all(key => ["kind", "value"].contains(key)) else {
    @failure.reject("invalid-operation", "Invalid cell value fields")
  }
  match field_string(content, "kind") {
    "blank" => {
      guard content is { "value": Null, .. } else {
        @failure.reject("invalid-operation", "Expected blank value")
      }
      @model.Blank
    }
    "text" => @model.Text(field_string(content, "value"))
    "error" => @model.Error(field_string(content, "value"))
    "number" => @model.Number(field_number(content, "value"))
    "boolean" => @model.Boolean(field_boolean(content, "value"))
    _ => @failure.reject("invalid-operation", "Unknown cell value kind")
  }
}
