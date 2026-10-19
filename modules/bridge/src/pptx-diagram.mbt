///|
fn pptx_diagram_edit(value : Json) -> @pptx.ObjectEdit raise @failure.Failure {
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
  @pptx.InsertDiagram({
    template: field_string(value, "template"),
    items: items.map(item => {
      guard item is String(text) else {
        @failure.reject("invalid-operation", "Diagram labels must be strings")
      }
      text
    }),
    x: xlsx_number(value, "x"),
    y: xlsx_number(value, "y"),
    width: xlsx_number(value, "width"),
    height: xlsx_number(value, "height"),
  })
}
