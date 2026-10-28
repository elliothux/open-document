///|
fn pptx_diagram_edit(value : Json) -> @model.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 7 &&
    fields
    .keys()
    .all(k => {
      ["action", "template", "items", "x", "y", "width", "height"].contains(k)
    }) &&
    fields.get("items") is Some(Array(items)) &&
    items.length() <= 16 else {
    @failure.reject("invalid-operation", "Invalid diagram fields")
  }
  @model.InsertDiagram({
    template: field_string(value, "template"),
    items: items.map(item => {
      guard item is String(text) else {
        @failure.reject("invalid-operation", "Diagram labels must be strings")
      }
      text
    }),
    x: field_number(value, "x"),
    y: field_number(value, "y"),
    width: field_number(value, "width"),
    height: field_number(value, "height"),
  })
}
