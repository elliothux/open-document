///|
fn object_markup(
  id : String,
  kind : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  text : String,
) -> String raise @failure.Failure {
  guard (kind == "text" || supported_shape(kind)) &&
    @xml.valid_text(text) &&
    !text.contains("\r") &&
    text.length() <= 32767 &&
    text.split("\n").count() <= 256 &&
    text.split("\n").all(p => p.length() <= 4096) &&
    (kind != "line" || text.is_empty()) else {
    @failure.reject("invalid-operation", "Invalid object kind or text")
  }
  validate_object_box(x, y, width, height, kind == "line")
  let text_box = kind == "text"
  let preset = if text_box { "rect" } else { kind }
  let fill = if text_box || kind == "line" {
    "<a:noFill/>"
  } else {
    "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>"
  }
  let stroke = if text_box {
    "<a:noFill/>"
  } else {
    "<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill>"
  }
  let body = if kind == "line" { "" } else { object_text_markup(text) }
  let markup = "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"\{kind} \{id}\"/><p:cNvSpPr txBox=\"\{if text_box { 1 } else { 0 }}\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(width * 12700).round().to_int64()}\" cy=\"\{(height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom>\{fill}<a:ln w=\"12700\">\{stroke}</a:ln></p:spPr>\{body}</p:sp>"
  markup
}
