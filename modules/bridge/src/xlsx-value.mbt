///|
fn xlsx_value(content : Json) -> @xlsx.Value raise @failure.Failure {
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
      @xlsx.Blank
    }
    "text" => @xlsx.Text(field_string(content, "value"))
    "error" => @xlsx.Error(field_string(content, "value"))
    "number" => @xlsx.Number(xlsx_number(content, "value"))
    "boolean" => @xlsx.Boolean(xlsx_boolean(content, "value"))
    _ => @failure.reject("invalid-operation", "Unknown cell value kind")
  }
}
