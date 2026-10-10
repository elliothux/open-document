///|
pub(all) struct Glyph {
  id : UInt
  cluster : Int
  font : Int
  outline : String
  x : Double
  y : Double
  scale : Double
  advance : Int
  yAdvance : Int
  xOffset : Int
  yOffset : Int
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
  start : Int
  end : Int
  level : Int
  font : Int
  script : String
  language : String
} derive(ToJson)

///|
pub extend GlyphRun with ToJson::{to_json}

///|
pub(all) struct FontInfo {
  identity : String
  face : Int
  variation : String
  upem : Int
  sha256 : String
  ascent : Int
  descent : Int
  bbox : Array[Int]
  capHeight : Int
  italicAngle : Double
} derive(ToJson)

///|
pub extend FontInfo with ToJson::{to_json}

///|
pub(all) struct GlyphDiagnostic {
  code : String
  cluster : Int
  codepoint : Int
} derive(ToJson)

///|
pub extend GlyphDiagnostic with ToJson::{to_json}

///|
pub(all) struct ShapeBatch {
  text : String
  glyphs : Array[Glyph]
  outlines : Array[Outline]
  runs : Array[GlyphRun]
  fonts : Array[FontInfo]
  diagnostics : Array[GlyphDiagnostic]
  width : Double
  fontBytes : Int
  outlineBytes : Int
} derive(ToJson)

///|
pub extend ShapeBatch with ToJson::{to_json}
