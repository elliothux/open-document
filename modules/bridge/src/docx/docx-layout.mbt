///|
priv struct LayoutIdRequest {
  layoutId : @common.RequestInt
} derive(@json.FromJson)

///|
fn Context::current_layout(
  self : Context,
  request : Json,
) -> @layout.Layout raise @failure.Failure {
  let command : LayoutIdRequest = @common.request(request)
  guard command.layoutId.value == self.layout_id && self.layout is Some(layout) else {
    @failure.reject(
      "stale-layout", "Geometry requires the current displayed layout",
    )
  }
  layout
}
