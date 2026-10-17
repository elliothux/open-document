///|
/// Returns the word at a UTF-16 grapheme boundary, preferring the word on its right.
pub fn word_range_at(text : String, offset : Int) -> (Int, Int)? {
  if offset < 0 ||
    offset > text.length() ||
    grapheme_boundaries(text).binary_search(offset) is Err(_) {
    return None
  }
  let mut before = None
  for (start, end) in @linebreak.word_indices_uax29(text) {
    if start > offset {
      break
    }
    if offset < end {
      return Some((start, end))
    }
    if offset == end {
      before = Some((start, end))
    }
  }
  before
}
