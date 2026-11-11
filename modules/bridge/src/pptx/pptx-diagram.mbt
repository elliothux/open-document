///|
#derive(@json.FromJson)
priv struct DiagramRequest {
  template : String
  items : Array[String]
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
}

///|
fn pptx_diagram_edit(value : Json) -> @model.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 7 &&
    fields.get("items") is Some(Array(items)) &&
    items.length() <= @model.DiagramItemCount else {
    @failure.reject("invalid-operation", "Invalid diagram fields")
  }
  let request : DiagramRequest = @common.request(value)
  @model.InsertDiagram({
    template: request.template,
    items: request.items,
    x: request.x.value,
    y: request.y.value,
    width: request.width.value,
    height: request.height.value,
  })
}
