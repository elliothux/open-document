///|
pub(all) struct PdfReadRun {
  text : String
  font : String
  identity : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
}

///|
pub(all) struct PdfReadLine {
  runs : Array[PdfReadRun]
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
}

///|
pub(all) struct PdfReadCell {
  row : Int32
  column : Int32
  rowSpan : Int32
  columnSpan : Int32
  lines : Array[PdfReadLine]
  fill : String
}

///|
pub(all) struct PdfReadTable {
  xs : Array[Double]
  ys : Array[Double]
  cells : Array[PdfReadCell]
  paths : Array[Int32]
}

///|
pub fn read_line_text(line : PdfReadLine) -> String {
  line.runs.map(run => run.text).join("")
}

///|
pub fn read_warning(warnings : Array[String], value : String) -> Unit {
  if !warnings.contains(value) {
    warnings.push(value)
  }
}

///|
pub fn read_bounds(points : Array[Double]) -> (Double, Double, Double, Double) {
  let mut x = 1000000000.0
  let mut y = 1000000000.0
  let mut r = -1000000000.0
  let mut b = -1000000000.0
  for i in 0..<(points.length() / 2) {
    x = x.min(points[i * 2])
    r = r.max(points[i * 2])
    y = y.min(points[i * 2 + 1])
    b = b.max(points[i * 2 + 1])
  }
  (x, y, r, b)
}
