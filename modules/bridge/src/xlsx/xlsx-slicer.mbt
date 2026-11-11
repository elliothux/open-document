///|
#derive(@json.FromJson)
priv struct SlicerHoverRequest {
  object : String
  index : @common.RequestInt
}

///|
fn xlsx_slicer_hover(request : Json) -> (String, Int32)? raise @failure.Failure {
  guard request is { "slicerHover": value, .. } else { return None }
  guard value is Object(fields) &&
    fields.length() == 2 &&
    fields.contains("object") &&
    fields.contains("index") else {
    @failure.reject("invalid-viewport", "Invalid slicer hover fields")
  }
  let hover : SlicerHoverRequest = @common.request(value)
  Some((hover.object, hover.index.value))
}
