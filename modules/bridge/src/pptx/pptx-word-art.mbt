///|
priv struct WordArtRequest {
  preset : String
  text : String
} derive(@json.FromJson)

///|
fn pptx_word_art_edit(value : Json) -> @model.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) && fields.length() == 3 else {
    @failure.reject("invalid-operation", "Invalid WordArt fields")
  }
  let request : WordArtRequest = @common.request(value)
  @model.InsertWordArt(request.preset, request.text)
}
