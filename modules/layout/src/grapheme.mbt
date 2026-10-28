///|
/// Extended grapheme boundaries in UTF-16 units, using Unicode 13.0.0 data.
pub fn grapheme_boundaries(text : String) -> Array[Int32] {
  [0, ..@linebreak.grapheme_indices_uax29(text).map(range => range.1)]
}
