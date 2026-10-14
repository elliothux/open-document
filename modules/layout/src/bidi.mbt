///|
fn bidi_control(codepoint : UInt) -> Bool {
  (codepoint >= 0x202aU && codepoint <= 0x202eU) ||
  (codepoint >= 0x2066U && codepoint <= 0x2069U)
}

///|
fn bidi_controls(paragraph : @bidi.BidiParagraph) -> @bidi.BidiParagraph {
  if !paragraph.chars.any(ch => bidi_control(ch.to_uint())) {
    return paragraph
  }
  let levels = paragraph.levels
  let mut next = paragraph.base_level
  for i = levels.length() - 1; i >= 0; i = i - 1 {
    // Writer's ICU retains X9 controls at the following character's level.
    if bidi_control(paragraph.chars[i].to_uint()) &&
      paragraph.original_classes[i].is_x9_removed() {
      levels[i] = next
    } else {
      next = levels[i]
    }
  }
  if levels.all(level => level % 2 == paragraph.base_level % 2) {
    levels.fill(paragraph.base_level)
  }
  paragraph
}

///|
fn bidi_order(paragraph : @bidi.BidiParagraph) -> Array[Int] {
  // Keep zero-width controls in the same visual portions as their source text.
  @bidi.reorder({
    ..paragraph,
    original_classes: paragraph.original_classes.mapi((i, value) => {
      if bidi_control(paragraph.chars[i].to_uint()) && value.is_x9_removed() {
        @bidi.ON
      } else {
        value
      }
    }),
  })
}

///|
fn Line::bidi_ranges(self : Line) -> Array[(Int, Int, Int)] {
  let ranges = []
  for run in self.runs {
    for range in run.bidi {
      ranges.push((run.start + range.start, run.start + range.end, range.level))
    }
  }
  ranges.sort_by((a, b) => a.0.compare(b.0))
  ranges
}

///|
fn Line::bidi_level(self : Line, offset : Int, affinity : String) -> Int {
  let offset = if affinity == "before" { offset - 1 } else { offset }
  for range in self.bidi_ranges() {
    if range.0 <= offset && offset < range.1 {
      return range.2
    }
  }
  self.baseLevel
}

///|
fn Line::bidi_portions(self : Line, depth : Int) -> Array[(Int, Int)] {
  let portions : Array[(Int, Int)] = []
  for range in self.bidi_ranges() {
    if range.2 < depth {
      continue
    }
    if portions.last() is Some(previous) && previous.1 == range.0 {
      portions[portions.length() - 1] = (previous.0, range.1)
    } else {
      portions.push((range.0, range.1))
    }
  }
  portions
}

///|
fn Line::bidi_bounds(self : Line, start : Int, end : Int) -> (Double, Double) {
  let mut left = 1.0 / 0.0
  let mut right = -1.0 / 0.0
  for index = 0; index + 1 < self.carets.length(); index = index + 1 {
    let a = self.carets[index]
    let b = self.carets[index + 1]
    if a.offset >= start && b.offset <= end {
      left = left.min(a.after.min(b.before))
      right = right.max(a.after.max(b.before))
    }
  }
  (left, right)
}

///|
fn Line::bidi_caret_x(
  self : Line,
  offset : Int,
  level : Int,
  fallback : Double,
) -> Double {
  let ranges = self.bidi_ranges()
  let maximum = ranges
    .iter()
    .fold(init=self.baseLevel, (value, range) => value.max(range.2))
  for depth = self.baseLevel + 1; depth <= maximum; depth = depth + 1 {
    for (start, end) in self.bidi_portions(depth) {
      if offset != start && offset != end {
        continue
      }
      let (left, right) = self.bidi_bounds(start, end)
      if left > right {
        return fallback
      }
      if offset == end && level >= depth {
        for (a, b) in self.bidi_portions(depth + 1) {
          if a >= start && b == end {
            let (inner_left, inner_right) = self.bidi_bounds(a, b)
            return if depth % 2 == 1 {
              left + inner_right - inner_left
            } else {
              right - inner_right + inner_left
            }
          }
        }
        for caret in self.carets {
          if caret.offset == offset {
            return caret.before
          }
        }
      }
      let leading = offset == start && level < depth
      return if (depth % 2 == 0) == leading { right } else { left }
    }
  }
  fallback
}

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
    if offset >= end {
      break
    }
    if offset >= start {
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
      other =>
        if other.is_x9_removed() {
          if trailing && bidi_control(line.chars[i].to_uint()) {
            levels[i] = paragraph.base_level
          }
        } else {
          trailing = false
        }
    }
  }
  line
}
