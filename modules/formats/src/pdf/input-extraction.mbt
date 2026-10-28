///|
pub(all) struct PdfExtractedGlyph {
  text : String
  encodedText : String
  font : String
  color : String
  fontIndex : Int32
  glyph : UInt32
  size : Double
  baseline : Array[Double]
  quad : Array[Double]
  inkQuad : Array[Double]
  transform : @layout.Matrix
  primitive : Int32
  group : Int32
  mapped : Bool
  invisible : Bool
  substituted : Bool
  marked : Bool
  clipped : Bool
  formDepth : Int32
  annotation : Bool
  cleanReason : String
}

///|
pub(all) struct PdfExtractedImage {
  key : String
  pixelWidth : Int32
  pixelHeight : Int32
  rgba : Bytes
  jpeg : Bytes?
  opacity : Double
  transform : @layout.Matrix
  quad : Array[Double]
  primitive : Int32
  reference : Int32
  formDepth : Int32
  clipped : Bool
  simpleForm : Bool
  annotation : Bool
  cleanReason : String
}

///|
pub(all) struct PdfExtractedPath {
  path : Array[@layout.PathSegment]
  fill : String
  stroke : String
  width : Double
  style : @layout.DrawStyle
  primitive : Int32
  clipped : Bool
  formDepth : Int32
  annotation : Bool
  cleanReason : String
}

///|
/// An independent, bounded extraction. Font indices and image keys belong to
/// this extraction and remain valid until `close` is called.
pub(all) struct PdfExtraction {
  page : String
  revision : Int32
  width : Double
  height : Double
  text : String
  textComplete : Bool
  displayComplete : Bool
  diagnostics : Array[String]
  glyphs : Array[PdfExtractedGlyph]
  images : Array[PdfExtractedImage]
  paths : Array[PdfExtractedPath]
  primitives : Array[@layout.PositionedPrimitive]
  probe : @layout.TextProbe
  resources : @layout.Images
}

///|
pub fn PdfExtraction::close(self : PdfExtraction) -> Unit {
  self.probe.close()
  self.resources.clear()
}

///|
priv struct PdfExtractionData {
  families : Map[Int32, String]
  mut clipBounds : @layout.Border?
  mut complexClip : Bool
  clipScopes : Array[(@layout.Border?, Bool)]
  formScopes : Array[Bool]
  glyphs : Array[PdfExtractedGlyph]
  glyphOrigins : Array[(Double, Double)]
  images : Array[PdfExtractedImage]
  paths : Array[PdfExtractedPath]
  glyphCommands : Map[Int32, Int32]
  imageCommands : Map[Int32, Int32]
  pathCommands : Map[Int32, Int32]
}

///|
fn PdfExtractionData::new() -> PdfExtractionData {
  {
    families: Map([]),
    clipBounds: None,
    complexClip: false,
    clipScopes: [],
    formScopes: [],
    glyphs: [],
    glyphOrigins: [],
    images: [],
    paths: [],
    glyphCommands: Map([]),
    imageCommands: Map([]),
    pathCommands: Map([]),
  }
}

///|
fn extraction_quad(transform : @layout.Matrix) -> Array[Double] {
  let (a, b) = transform.point(0, 0)
  let (c, d) = transform.point(1, 0)
  let (e, f) = transform.point(1, 1)
  let (g, h) = transform.point(0, 1)
  [a, b, c, d, e, f, g, h]
}

///|
fn extraction_scale(transform : @layout.Matrix) -> Double {
  let trace = transform.a * transform.a +
    transform.b * transform.b +
    transform.c * transform.c +
    transform.d * transform.d
  let determinant = transform.a * transform.d - transform.b * transform.c
  ((trace + (trace * trace - 4 * determinant * determinant).max(0).sqrt()) / 2).sqrt()
}

///|
fn extraction_style_reason(
  style : @layout.DrawStyle,
  text~ : Bool = false,
) -> String {
  if style.multiply {
    "Source blend mode is not represented by the native clean writer"
  } else if style.dashOffset != 0 || style.evenOdd {
    "Source path fill or dash state requires explicit reconstruction"
  } else if text && (style.fillAlpha != 1 || style.strokeAlpha != 1) {
    "Source text transparency requires explicit reconstruction"
  } else {
    ""
  }
}
