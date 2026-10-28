///|
pub struct LiteralPattern {
  priv chars : Array[Char]
  priv prefix : Array[Int32]
  priv match_case : Bool
  priv whole_word : Bool
}

///|
/// Prepare bounded literal search using the editor's simple Unicode lowercase rule.
pub fn LiteralPattern::new(
  text : String,
  match_case~ : Bool = false,
  whole_word~ : Bool = false,
) -> LiteralPattern raise @failure.Failure {
  guard !text.is_empty() && text.length() <= 65536 else {
    @failure.reject(
      "invalid-operation", "Search requires bounded nonempty text",
    )
  }
  let chars = text
    .iter()
    .map(ch => if match_case { ch } else { @ucd.to_lowercase(ch) })
    .to_array()
  let prefix = Array::make(chars.length(), 0)
  for i in 1..<chars.length() {
    let mut matched = prefix[i - 1]
    while matched > 0 && chars[i] != chars[matched] {
      matched = prefix[matched - 1]
    }
    if chars[i] == chars[matched] {
      matched += 1
    }
    prefix[i] = matched
  }
  { chars, prefix, match_case, whole_word, }
}

///|
fn search_word_char(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() ||
  ch.is_ascii_digit() ||
  (!ch.is_ascii() && @ucd.non_ascii_id_continue.contains(ch))
}

///|
/// Return at most 1001 nonoverlapping UTF-16 ranges on whole grapheme boundaries.
pub fn LiteralPattern::matches(
  self : LiteralPattern,
  text : String,
) -> Array[(Int32, Int32)] {
  let chars : Array[(Int32, Char)] = []
  let mut offset = 0
  for ch in text {
    chars.push((offset, ch))
    offset += if ch.to_int() > 0xffff { 2 } else { 1 }
  }
  let boundaries = grapheme_boundaries(text)
  let matches : Array[(Int32, Int32)] = []
  let mut matched = 0
  for index, (offset, ch) in chars {
    let value = if self.match_case { ch } else { @ucd.to_lowercase(ch) }
    while matched > 0 && value != self.chars[matched] {
      matched = self.prefix[matched - 1]
    }
    if value == self.chars[matched] {
      matched += 1
    }
    if matched != self.chars.length() {
      continue
    }
    let first = index + 1 - matched
    let start = chars[first].0
    let end = offset + (if ch.to_int() > 0xffff { 2 } else { 1 })
    let whole = !self.whole_word ||
      (
        (first == 0 || !search_word_char(chars[first - 1].1)) &&
        (index + 1 == chars.length() || !search_word_char(chars[index + 1].1))
      )
    if whole &&
      boundaries.binary_search(start) is Ok(_) &&
      boundaries.binary_search(end) is Ok(_) {
      matches.push((start, end))
      if matches.length() == 1001 {
        break
      }
      matched = 0
    } else {
      matched = self.prefix[matched - 1]
    }
  }
  matches
}
