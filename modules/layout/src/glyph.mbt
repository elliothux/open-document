///|
pub(all) struct Glyph {
  id : UInt32
  cluster : Int32
  font : Int32
  outline : String
  x : Double
  y : Double
  scale : Double
  advance : Int32
  yAdvance : Int32
  xOffset : Int32
  yOffset : Int32
} derive(ToJson)

///|
pub extend Glyph with ToJson::{to_json}

///|
pub(all) struct Outline {
  key : String
  path : String
} derive(ToJson)

///|
pub extend Outline with ToJson::{to_json}

///|
pub(all) struct GlyphRun {
  start : Int32
  end : Int32
  level : Int32
  font : Int32
  script : String
  language : String
} derive(ToJson)

///|
pub extend GlyphRun with ToJson::{to_json}

///|
pub(all) struct FontInfo {
  identity : String
  face : Int32
  variation : String
  upem : Int32
  sha256 : String
  ascent : Int32
  descent : Int32
  bbox : Array[Int32]
  capHeight : Int32
  italicAngle : Double
} derive(ToJson)

///|
pub extend FontInfo with ToJson::{to_json}

///|
pub(all) struct GlyphDiagnostic {
  code : String
  cluster : Int32
  codepoint : Int32
} derive(ToJson)

///|
pub extend GlyphDiagnostic with ToJson::{to_json}

///|
pub(all) struct ShapeBatch {
  text : String
  carets : Array[Caret]
  glyphs : Array[Glyph]
  outlines : Array[Outline]
  runs : Array[GlyphRun]
  fonts : Array[FontInfo]
  diagnostics : Array[GlyphDiagnostic]
  width : Double
  fontBytes : Int32
  outlineBytes : Int32
} derive(ToJson)

///|
pub extend ShapeBatch with ToJson::{to_json}
