///|
priv struct GuideVisibilityRequest {
  visible : Bool
} derive(@json.FromJson)

///|
priv struct GuideItemRequest {
  orientation : String
  position : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct SnappingRequest {
  grid : Bool
  objects : Bool
  spacing : @common.RequestNumber
} derive(@json.FromJson)

///|
fn pptx_guide_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields.get("items") is Some(Array(items)) &&
    items.length() <= @model.GuideCount else {
    @failure.reject(
      "invalid-operation", "A bounded presentation guide list is required",
    )
  }
  let request : GuideVisibilityRequest = @common.request(change)
  @model.Guides(
    request.visible,
    items.map(item => {
      guard item is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid presentation guide")
      }
      let guide : GuideItemRequest = @common.request(item)
      { orientation: guide.orientation, position: guide.position.value, }
    }),
  )
}

///|
fn pptx_snapping_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is Object(fields) && fields.length() == 4 else {
    @failure.reject(
      "invalid-operation", "Snapping requires grid, objects and spacing",
    )
  }
  let request : SnappingRequest = @common.request(change)
  @model.Snapping({
    grid: request.grid,
    objects: request.objects,
    spacing: request.spacing.value,
  })
}
