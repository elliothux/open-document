///|
fn pptx_guide_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields.get("items") is Some(Array(items)) &&
    items.length() <= 64 else {
    @failure.reject(
      "invalid-operation", "A bounded presentation guide list is required",
    )
  }
  @model.Guides(
    field_boolean(change, "visible"),
    items.map(item => {
      guard item is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid presentation guide")
      }
      {
        orientation: field_string(item, "orientation"),
        position: field_number(item, "position"),
      }
    }),
  )
}

///|
fn pptx_snapping_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) && fields.length() == 4 else {
    @failure.reject(
      "invalid-operation", "Snapping requires grid, objects and spacing",
    )
  }
  @model.Snapping({
    grid: field_boolean(change, "grid"),
    objects: field_boolean(change, "objects"),
    spacing: field_number(change, "spacing"),
  })
}
