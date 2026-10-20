///|
fn pptx_word_art_edit(value : Json) -> @pptx.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.keys().all(key => ["action", "preset", "text"].contains(key)) else {
    @failure.reject("invalid-operation", "Invalid WordArt fields")
  }
  @pptx.InsertWordArt(
    field_string(value, "preset"),
    field_string(value, "text"),
  )
}
