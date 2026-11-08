///|
pub(all) struct Resource {
  part : String
  workbook : String
  data : @layout.ChartData
  native_pie : NativePie?
}

///|
pub fn Resource::paint(
  self : Resource,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if self.native_pie is Some(pie) {
    self.data.paint_native_pie(
      width,
      height,
      pie.colors,
      pie.explosions,
      pie.first_angle,
    )
  } else {
    self.data.paint(width, height, probe, profile)
  }
}
