///|
pub struct ChartFrame {
  data : ChartData
  primitives : Array[PositionedPrimitive]
}

///|
pub fn ChartFrame::new(data : ChartData) -> ChartFrame {
  { data: data.copy(), primitives: [], }
}

///|
fn ChartData::copy(self : ChartData) -> ChartData {
  {
    ..self,
    categories: self.categories.copy(),
    series: self.series.map(series => {
      ..series,
      values: series.values.copy(),
    }),
  }
}

///|
pub impl ToJson for ChartFrame with fn to_json(self) {
  self.data.query()
}

///|
pub extend ChartFrame with ToJson::{to_json}

///|
fn ChartFrame::copy(self : ChartFrame) -> ChartFrame {
  { data: self.data.copy(), primitives: self.primitives.copy(), }
}

///|
fn ChartFrame::prepare(
  self : ChartFrame,
  frame : DrawingFrame,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  {
    ..frame,
    content: Chart({
      ..self,
      primitives: self.data.paint(frame.width, frame.height, probe, profile),
    }),
  }
}

///|
fn ChartFrame::cache_units(self : ChartFrame) -> Int {
  positioned_cache_units([self.data.query().stringify()], self.primitives)
}
