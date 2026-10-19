///|
fn pptx_image_insets(change : Json) -> Array[Double] raise @failure.Failure {
  guard change is { "insets": Array(values), .. } && values.length() == 4 else {
    @failure.reject(
      "invalid-operation", "Four image destination insets are required",
    )
  }
  values.map(value => {
    match value {
      Number(value, ..) => value
      _ =>
        @failure.reject("invalid-operation", "Invalid image destination inset")
    }
  })
}
