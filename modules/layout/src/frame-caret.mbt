///|
fn Layout::frame_caret(
  self : Layout,
  paragraph : Int,
  offset : Int,
  affinity : String,
  frame_start : Int,
  bidi_level : Int?,
) -> Hit? {
  let mut previous : (Int, Line)? = None
  for page, frame in self.pages {
    for index, line in frame.lines {
      if line.paragraph != paragraph {
        continue
      }
      if line.start == frame_start &&
        previous is Some((before_page, before)) &&
        before_page != page &&
        before.end == frame_start &&
        before.carets.get(before.carets.length() - 2) is Some(boundary) &&
        boundary.offset == offset &&
        line.carets.get(0) is Some(first) &&
        first.offset == frame_start {
        let default_level = line.bidi_level(first.offset, affinity)
        let level = bidi_level.unwrap_or(default_level)
        let visual = {
          ..line_hit(line, page, index, first, affinity),
          bidiLevel: Some(level),
        }
        // A retained follow-frame cursor still edits at the preceding logical boundary.
        return Some({
          ..visual,
          offset,
          frameStart: Some(frame_start),
          bidiLevel: if level == default_level {
            None
          } else {
            Some(level)
          },
        })
      }
      previous = Some((page, line))
    }
  }
  None
}
