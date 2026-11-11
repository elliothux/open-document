///|
fn xlsx_drawing_viewport(
  request : Json,
) -> @model.DrawingViewport? raise @failure.Failure {
  guard request is { "viewport": value, .. } else { return None }
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields
    .keys()
    .all(key => ["originX", "originY", "scrollX", "scrollY"].contains(key)) else {
    @failure.reject(
      "invalid-viewport", "Invalid worksheet object pointer viewport fields",
    )
  }
  Some(drawing_viewport(value))
}

///|
fn drawing_viewport(
  input : Json,
) -> @model.DrawingViewport raise @failure.Failure {
  let command : DrawingViewportRequest = @common.request(input)
  {
    origin_x: command.originX.value,
    origin_y: command.originY.value,
    scroll_x: command.scrollX.value,
    scroll_y: command.scrollY.value,
  }
}

///|
#derive(@json.FromJson)
priv struct MoveDrawingRequest {
  sourceSheet : String
  objectId : String
}

///|
#derive(@json.FromJson)
priv struct DuplicateDrawingRequest {
  objectId : String
}

///|
#derive(@json.FromJson)
priv struct DrawingOrderRequest {
  objectId : String
  direction : String
}

///|
fn xlsx_move_drawing(change : Json) -> @model.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields
    .keys()
    .all(key => ["action", "sourceSheet", "objectId"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet drawing move fields",
    )
  }
  let input : MoveDrawingRequest = @common.request(change)
  @model.MoveDrawing(input.sourceSheet, input.objectId)
}

///|
fn xlsx_duplicate_drawing(
  change : Json,
) -> @model.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 2 &&
    fields.keys().all(key => ["action", "objectId"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet drawing copy fields",
    )
  }
  let input : DuplicateDrawingRequest = @common.request(change)
  @model.DuplicateDrawing(input.objectId)
}

///|
fn xlsx_drawing_order(change : Json) -> @model.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields.keys().all(key => ["action", "objectId", "direction"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet picture layer command fields",
    )
  }
  let input : DrawingOrderRequest = @common.request(change)
  @model.DrawingOrder(input.objectId, input.direction)
}
