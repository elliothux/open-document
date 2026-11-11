///|
priv struct ObjectSelectionRequest {
  values : Array[Json]
}

///|
impl @json.FromJson for ObjectSelectionRequest with fn from_json(input, path) {
  guard input is Array(values) && values.length() <= @model.ObjectSelectionCount else {
    raise @json.JsonDecodeError(
      (path, "A bounded object selection is required"),
    )
  }
  { values, }
}

///|
fn ObjectSelectionRequest::identities(
  self : ObjectSelectionRequest,
) -> Array[String] raise @failure.Failure {
  self.values.map(value => {
    guard value is String(id) && id.length() <= 1024 else {
      @failure.reject("invalid-object", "Invalid selected object identity")
    }
    id
  })
}
