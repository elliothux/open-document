///|
/// Inserts an inline ordinary shape at the current selection as one source transaction.
pub fn Session::insert_shape(
  self : Session,
  revision : Int,
  preset : String,
  width : Double,
  height : Double,
  fill : String,
  stroke : String,
  line_width : Double,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let (width, height, line_width) = check_shape_properties(
    preset, width, height, fill, stroke, line_width,
  )
  let identity = self.next_drawing_identity()
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  let paint = shape_fill_markup(fill.to_upper())
  let line = shape_fill_markup(stroke.to_upper())
  let weight = (line_width * 12700).round().to_int64()
  let markup = "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:wps=\"\{word_shape_uri}\"><wp:inline><wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:docPr id=\"\{identity}\" name=\"Shape \{identity}\"/><a:graphic><a:graphicData uri=\"\{word_shape_uri}\"><wps:wsp><wps:cNvSpPr/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom>\{paint}<a:ln w=\"\{weight}\">\{line}</a:ln></wps:spPr><wps:bodyPr/></wps:wsp></a:graphicData></a:graphic></wp:inline></od:drawing>"
  let prepared = self.prepare_drawing_insertion(markup)
  self.check_picture_layout(prepared.document, probe, profile, images)
  self.commit_edit(prepared.edit, prepared.document)
  self.edit_result(prepared.edit.paragraphs)
}
