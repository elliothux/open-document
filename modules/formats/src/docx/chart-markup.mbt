///|
fn chart_markup(
  id : Int,
  link : String,
  width : Double,
  height : Double,
) -> String {
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:c=\"\{chart_uri}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:docPr id=\"\{id}\" name=\"Chart \{id}\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"\{chart_uri}\"><c:chart r:id=\"\{link}\"/></a:graphicData></a:graphic></wp:inline></od:drawing>"
}
