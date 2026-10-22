///|
fn chart_frame(
  id : String,
  link : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> String {
  "<p:graphicFrame xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:c=\"\{chart_uri}\" xmlns:r=\"\{relationship_uri}\"><p:nvGraphicFramePr><p:cNvPr id=\"\{id}\" name=\"Chart \{id}\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\{(x*12700).round().to_int64()}\" y=\"\{(y*12700).round().to_int64()}\"/><a:ext cx=\"\{(width*12700).round().to_int64()}\" cy=\"\{(height*12700).round().to_int64()}\"/></p:xfrm><a:graphic><a:graphicData uri=\"\{chart_uri}\"><c:chart r:id=\"\{link}\"/></a:graphicData></a:graphic></p:graphicFrame>"
}
