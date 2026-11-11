///|
#derive(@json.FromJson(fields(cycling(rename="loop"))))
priv struct ShowSettingsRequest {
  slides : Json
  timings : Bool
  animations : Bool
  cycling : Bool
}

///|
#derive(@json.FromJson)
priv struct ShowRangeRequest {
  first : @common.RequestInt
  last : @common.RequestInt
}

///|
fn pptx_show_settings(change : Json) -> @model.SlideEdit raise @failure.Failure {
  guard change is { "value": Object(fields) as value, .. } &&
    fields.length() == 4 else {
    @failure.reject("invalid-operation", "Invalid show settings fields")
  }
  let request : ShowSettingsRequest = @common.request(value)
  let slides = request.slides
  guard slides is { "kind": String(kind), .. } && slides is Object(items) else {
    @failure.reject("invalid-operation", "Invalid show selection fields")
  }
  @model.Settings({
    slides: match kind {
      "all" if items.length() == 1 => @model.ShowAll
      "range" if items.length() == 3 => {
        let range : ShowRangeRequest = @common.request(slides)
        @model.ShowRange(range.first.value, range.last.value)
      }
      "custom" if items.length() == 2 => {
        let custom : IdRequest = @common.request(slides)
        @model.ShowCustom(custom.id)
      }
      _ => @failure.reject("invalid-operation", "Invalid show selection fields")
    },
    timings: request.timings,
    animations: request.animations,
    cycling: request.cycling,
  })
}
