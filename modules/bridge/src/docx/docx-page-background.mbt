///|
fn page_background_color(request : Json) -> String? raise @failure.Failure {
  match request {
    { "color": Null, .. } => None
    { "color": String(value), .. } => Some(value)
    _ =>
      @failure.reject(
        "invalid-operation", "Page background requires a color or null",
      )
  }
}
