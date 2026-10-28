///|
fn Context::current_layout(
  self : Context,
  request : Json,
) -> @layout.Layout raise @failure.Failure {
  guard field_int(request, "layoutId") == self.layout_id &&
    self.layout is Some(layout) else {
    @failure.reject(
      "stale-layout", "Geometry requires the current displayed layout",
    )
  }
  layout
}
