///|
fn pptx_placeholder(change : Json) -> @model.ObjectEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 2 &&
    fields.get("value") is Some(value) else {
    @failure.reject("invalid-operation", "Invalid placeholder edit fields")
  }
  if value is Null {
    return @model.Placeholder(None, 0)
  }
  guard value is Object(fields) && fields.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid placeholder definition")
  }
  @model.Placeholder(
    Some(field_string(value, "type")),
    field_number(value, "index"),
  )
}

///|
fn pptx_insert_object(
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  let action = field_string(change, "action")
  let x = field_number(change, "x")
  let y = field_number(change, "y")
  let width = field_number(change, "width")
  let height = field_number(change, "height")
  let text = field_string(change, "text")
  if action == "insert" {
    return @model.Insert(
      field_string(change, "kind"),
      x,
      y,
      width,
      height,
      text,
    )
  }
  guard action == "insertPlaceholder" &&
    change is Object(fields) &&
    fields.length() == 7 else {
    @failure.reject("invalid-operation", "Invalid placeholder insertion fields")
  }
  @model.InsertPlaceholder(
    field_string(change, "type"),
    x,
    y,
    width,
    height,
    text,
  )
}
