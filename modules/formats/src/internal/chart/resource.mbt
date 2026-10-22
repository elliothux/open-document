///|
pub(all) struct Resource {
  part : String
  workbook : String
  data : @layout.ChartData
}

///|
pub fn Resource::paint(
  self : Resource,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  self.data.paint(width, height, probe, profile)
}
