///|
fn bidi_slice(
  paragraph : @bidi.BidiParagraph,
  start : Int,
  end : Int,
) -> @bidi.BidiParagraph {
  let chars = []
  let original_classes = []
  let resolved_classes = []
  let levels = []
  let mut offset = 0
  for i, ch in paragraph.chars {
    if offset >= start && offset < end {
      chars.push(ch)
      original_classes.push(paragraph.original_classes[i])
      resolved_classes.push(paragraph.resolved_classes[i])
      levels.push(paragraph.levels[i])
    }
    offset += if ch.to_int() > 0xffff { 2 } else { 1 }
  }
  {
    chars,
    original_classes,
    resolved_classes,
    levels,
    base_level: paragraph.base_level,
  }
}

///|
fn bidi_line(
  paragraph : @bidi.BidiParagraph,
  start : Int,
  end : Int,
) -> @bidi.BidiParagraph {
  let line = bidi_slice(paragraph, start, end)
  let levels = line.levels
  // UAX #9 L1 resets trailing whitespace for this line, not a new paragraph.
  let mut trailing = true
  for i = levels.length() - 1; i >= 0; i = i - 1 {
    match line.original_classes[i] {
      @bidi.B | @bidi.S => {
        levels[i] = paragraph.base_level
        trailing = true
      }
      @bidi.WS | @bidi.FSI | @bidi.LRI | @bidi.RLI | @bidi.PDI =>
        if trailing {
          levels[i] = paragraph.base_level
        }
      other => if !other.is_x9_removed() { trailing = false }
    }
  }
  line
}
