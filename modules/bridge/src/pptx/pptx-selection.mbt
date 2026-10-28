///|
fn pptx_objects(request : Json) -> Array[String] raise @failure.Failure {
  guard request is Object(fields) &&
    fields.get("objects") is Some(Array(values)) &&
    values.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "A bounded object selection is required",
    )
  }
  values.map(value => {
    guard value is String(id) && id.length() <= 1024 else {
      @failure.reject("invalid-object", "Invalid selected object identity")
    }
    id
  })
}
