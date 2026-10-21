///|
fn picture_markup(
  identity : Int,
  link : String,
  width : Double,
  height : Double,
  alt~ : String = "",
  title~ : String = "",
  bytes~ : String? = None,
) -> String raise @failure.Failure {
  let description = (if alt.is_empty() {
      ""
    } else {
      " descr=\"" + property_attribute(alt) + "\""
    }) +
    (if title.is_empty() {
      ""
    } else {
      " title=\"" + property_attribute(title) + "\""
    })
  let portable = bytes
    .map(value => {
      " xmlns:odClip=\"" +
      table_fragment_uri +
      "\" odClip:bytes=\"" +
      value +
      "\""
    })
    .unwrap_or("")
  let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let picture = "http://schemas.openxmlformats.org/drawingml/2006/picture"
  let cx = (width * 12700).round().to_int64().to_string()
  let cy = (height * 12700).round().to_int64().to_string()
  let drawing = "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:pic=\"\{picture}\" xmlns:r=\"\{rel}\"><wp:inline><wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:docPr id=\"\{identity}\" name=\"Picture \{identity}\"\{description}/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri=\"\{picture}\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\{identity}\" name=\"Picture \{identity}\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\{property_attribute(link)}\"\{portable}/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></od:drawing>"
  drawing
}
