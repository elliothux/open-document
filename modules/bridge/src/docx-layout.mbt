///|
fn Foundation::current_layout(
  self : Foundation,
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
