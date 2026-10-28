///|
fn script_font_class(script : String) -> Int32 {
  match script {
    "Bopo" | "Hani" | "Hang" | "Hira" | "Kana" | "Yiii" | "Tang" | "Kits" => 1
    "Armn"
    | "Cher"
    | "Copt"
    | "Cyrl"
    | "Geor"
    | "Goth"
    | "Grek"
    | "Latn"
    | "Ogam"
    | "Ital"
    | "Runr"
    | "Cans"
    | "Brai"
    | "Cprt"
    | "Osma"
    | "Shaw"
    | "Hrkt"
    | "Glag"
    | "Hung" => 0
    _ => 2
  }
}

///|
fn character_font_class(codepoint : UInt32, inherited : Int32) -> Int32 {
  match codepoint {
    1U
    | 2U
    | 0x20U
    | 0xA0U
    | 0xB2U
    | 0xB3U
    | 0xB9U
    | 0x2C7U
    | 0x2CAU
    | 0x2CBU
    | 0x2D9U => return inherited
    _ => ()
  }
  if codepoint >= 0x2160U && codepoint <= 0x218FU {
    return inherited
  }
  // Writer retains block-based font classes for numbers and Asian punctuation.
  if codepoint <= 0x2FFU || (codepoint >= 0x370U && codepoint <= 0x58FU) {
    return 0
  }
  if (codepoint >= 0x2E80U && codepoint <= 0x303FU) ||
    (codepoint >= 0x3130U && codepoint <= 0x319FU) ||
    (codepoint >= 0x31C0U && codepoint <= 0x33FFU) ||
    (codepoint >= 0xFE30U && codepoint <= 0xFE4FU) ||
    (codepoint >= 0xFF00U && codepoint <= 0xFFEFU) {
    return 1
  }
  let tag = @unicode.script(codepoint).to_iso15924_tag().to_string()
  if tag == "Zyyy" || tag == "Zinh" {
    inherited
  } else {
    script_font_class(tag)
  }
}

///|
fn letter_numeric_at(text : String, offset : Int32) -> Bool {
  if offset < 0 || offset >= text.length() {
    return false
  }
  let first = text[offset].to_int()
  let codepoint = if first >= 0xD800 &&
    first <= 0xDBFF &&
    offset + 1 < text.length() &&
    text[offset + 1] >= 0xDC00 &&
    text[offset + 1] <= 0xDFFF {
    0x10000 + (first - 0xD800) * 1024 + text[offset + 1].to_int() - 0xDC00
  } else {
    first
  }
  let category = @unicode.general_category(codepoint.reinterpret_as_uint())
  (
    category >= @unicode.gc_lowercase_letter &&
    category <= @unicode.gc_uppercase_letter
  ) ||
  (
    category >= @unicode.gc_decimal_number &&
    category <= @unicode.gc_other_number
  )
}

///|
fn script_spaces(
  spans : Array[MeasuredSpan],
  text : String,
  bidi : @bidi.BidiParagraph,
) -> Map[Int32, Double] {
  let spaces : Map[Int32, Double] = Map([])
  let mut previous = 0
  let mut offset = 0
  let mut span = 0
  for i, ch in bidi.chars {
    let current = character_font_class(ch.to_uint(), previous)
    // Exiting a Writer BiDi portion does not leave a preceding text portion.
    if offset > 0 &&
      bidi.levels[i - 1] <= bidi.levels[i] &&
      current != previous &&
      (current == 1 || previous == 1) &&
      letter_numeric_at(text, offset - 1) &&
      letter_numeric_at(text, offset) {
      while span < spans.length() && spans[span].end <= offset - 1 {
        span += 1
      }
      if span < spans.length() && spans[span].font >= 0 {
        let width = ((spans[span].span.style.size * 20).floor() / 5).floor() /
          20
        if width > 0 {
          spaces[offset] = width
        }
      }
    }
    previous = current
    offset += if ch.to_int() > 0xFFFF { 2 } else { 1 }
  }
  spaces
}
