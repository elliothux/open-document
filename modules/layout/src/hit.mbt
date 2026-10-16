///|
pub(all) struct Hit {
  paragraph : Int
  offset : Int
  affinity : String
  bidiLevel : Int?
  frameStart : Int?
  page : Int
  line : Int
  x : Double
  y : Double
  height : Double
  reason : String
} derive(ToJson)

///|
pub extend Hit with ToJson::{to_json}

///|
fn Layout::caret_geometry(self : Layout, hit : Hit) -> Hit {
  if hit.frameStart is Some(start) {
    let visual = self.caret_geometry({ ..hit, offset: start, frameStart: None, })
    return { ..visual, offset: hit.offset, frameStart: hit.frameStart, }
  }
  let line = self.pages[hit.page].lines[hit.line]
  let level = hit.bidiLevel.unwrap_or_else(() => {
    line.bidi_level(hit.offset, hit.affinity)
  })
  let hit = { ..hit, x: line.bidi_caret_x(hit.offset, level, hit.x), }
  let mut multiple = line.runs.length() > 1 || !line.images.is_empty()
  if !multiple {
    multiple = line.bidi_ranges().iter().any(range => range.2 > line.baseLevel)
  }
  if !multiple && line.end > line.start {
    // A following bidi portion can split the sole text portion before wrapping.
    multiple = self.pages
      .iter()
      .any(frame => {
        frame.lines
        .iter()
        .any(next => {
          next.paragraph == line.paragraph &&
          next.start == line.end &&
          next.bidi_level(next.start, "after") > next.baseLevel
        })
      })
  }
  if !multiple && line.runs.get(0) is Some(run) {
    let advance = run.glyphs
      .iter()
      .fold(init=0.0, (sum, glyph) => {
        sum + glyph.advance.to_double() * glyph.scale
      })
    multiple = line.width > advance + 1.0e-7
  }
  let mut script : Int? = None
  if !multiple {
    for ch in line.text.iter() {
      let category = character_font_class(ch.to_uint(), script.unwrap_or(0))
      if script is Some(previous) && previous != category {
        multiple = true
        break
      }
      script = Some(category)
    }
  }
  // Writer reuses the line as its sole text portion, including exact line height.
  if !multiple {
    return hit
  }
  let mut chosen : (PlacedRun, Glyph)? = None
  let mut control : (PlacedRun, Int)? = None
  for run in line.runs {
    let index = hit.offset - run.start - 1
    if index >= 0 &&
      index < run.text.length() &&
      (bidi_control(run.text[index].to_uint()) || run.text[index] == 9) {
      for range in run.bidi {
        if range.start <= index && index < range.end {
          control = Some((run, range.font))
        }
      }
    }
  }
  let mut start = -1
  for run in line.runs {
    for glyph in run.glyphs {
      let offset = run.start + glyph.cluster
      // At a format boundary Writer uses the preceding text portion's metrics.
      if (
          offset < hit.offset ||
          (hit.offset == line.start && offset == line.start)
        ) &&
        offset > start {
        start = offset
        chosen = Some((run, glyph))
      }
    }
  }
  let (run, index, size) = match (control, chosen) {
    (Some((run, font)), _) => (run, font, run.size)
    (_, Some((run, glyph))) =>
      (run, glyph.font, glyph.scale * self.fonts[glyph.font].upem.to_double())
    _ => return hit
  }
  let font = self.fonts[index]
  let (a, d) = scaled_line_metrics(font.ascent, font.descent, font.upem, size)
  let mut ascent = a
  let mut descent = d
  for (start, end) in line.bidi_portions(line.baseLevel + 1) {
    if hit.offset == end && level > line.baseLevel {
      // At a multi-portion's end Writer retains the enclosing portion metrics.
      for candidate in line.runs {
        for glyph in candidate.glyphs {
          let offset = candidate.start + glyph.cluster
          if start <= offset && offset < end {
            let font = self.fonts[glyph.font]
            let (a, d) = scaled_line_metrics(
              font.ascent,
              font.descent,
              font.upem,
              glyph.scale * font.upem.to_double(),
            )
            ascent = ascent.max(a)
            descent = descent.max(d)
          }
        }
      }
    }
  }
  let y = line.y.max(run.baseline - ascent)
  let mut bottom = line.y + line.height
  for candidate in self.pages[hit.page].lines {
    if candidate.paragraph == line.paragraph {
      bottom = bottom.max(candidate.y + candidate.height)
    }
  }
  {
    ..hit,
    y,
    height: line.height.min(ascent + descent).min((bottom - y).max(0)),
  }
}

///|
fn line_hit(
  line : Line,
  page : Int,
  index : Int,
  caret : Caret,
  affinity : String,
) -> Hit {
  {
    paragraph: line.paragraph,
    offset: caret.offset,
    affinity,
    bidiLevel: None,
    frameStart: None,
    page,
    line: index,
    x: if affinity == "before" {
      caret.before
    } else {
      caret.after
    },
    y: line.y,
    height: line.height,
    reason: line.readOnlyReason,
  }
}

///|
/// Queries point coordinates in one completed page; it never changes selection.
pub fn Layout::hit_test(
  self : Layout,
  page : Int,
  x : Double,
  y : Double,
) -> Hit raise @failure.Failure {
  guard page >= 0 && page < self.pages.length() else {
    @failure.reject("invalid-page", "Unknown hit-test page")
  }
  let frame = self.pages[page]
  guard x >= 0 && x <= frame.width && y >= 0 && y <= frame.height else {
    @failure.reject(
      "invalid-position", "Hit coordinates must be finite and inside the page",
    )
  }
  let mut chosen = -1
  let mut vertical = frame.height + 1
  let mut horizontal = frame.width + 1
  let cell = frame.cellAreas
    .iter()
    .find_first(area => {
      x >= area.x &&
      x < area.x + area.width &&
      y >= area.y &&
      y < area.y + area.height
    })
  for index, line in frame.lines {
    if line.caretOnly ||
      (cell is Some(area) && !area.paragraphs.contains(line.paragraph)) {
      continue
    }
    for image in line.images {
      if x >= image.x &&
        x <= image.x + image.width &&
        y >= image.y &&
        y <= image.y + image.height &&
        (!line.clip || (y >= line.y && y <= line.y + line.height)) {
        return {
          paragraph: line.paragraph,
          offset: 0,
          affinity: "after",
          bidiLevel: None,
          frameStart: None,
          page,
          line: index,
          x: image.x,
          y: image.y,
          height: image.height,
          reason: "Inline image is protected",
        }
      }
    }
    if line.carets.is_empty() {
      continue
    }
    let dy = (line.y - y).max(0) + (y - line.y - line.height).max(0)
    let dx = (line.x - x).max(0) + (x - line.x - line.width).max(0)
    if dy < vertical || (dy == vertical && dx < horizontal) {
      chosen = index
      vertical = dy
      horizontal = dx
    }
  }
  guard chosen >= 0 else {
    @failure.reject("invalid-position", "Page has no text position")
  }
  let hit = nearest_caret(frame.lines[chosen], page, chosen, x)
  if frame.lines[chosen].repeated {
    self.caret(hit.paragraph, hit.offset, hit.affinity)
  } else {
    self.caret_geometry(hit)
  }
}

///|
fn nearest_caret(line : Line, page : Int, index : Int, x : Double) -> Hit {
  let first = line.carets[0].offset
  let last = line.carets.last().unwrap().offset
  let mut best = line_hit(line, page, index, line.carets[0], "after")
  let mut distance = (x - best.x).abs()
  for caret in line.carets {
    for affinity in ["before", "after"] {
      if (caret.offset == first && affinity == "before") ||
        (first != last && caret.offset == last && affinity == "after") {
        continue
      }
      let candidate = line_hit(line, page, index, caret, affinity)
      let dx = (x - candidate.x).abs()
      if dx < distance ||
        (dx == distance && affinity == "after" && best.affinity == "before") {
        best = candidate
        distance = dx
      }
    }
  }
  let graphemes = line.visual_graphemes(page, index)
  for grapheme in graphemes {
    let left = grapheme.left
    let right = grapheme.right
    if x <= left.x || x > right.x {
      continue
    }
    // Writer leaves an RTL portion at its logical end on the right boundary.
    if left.offset > right.offset && x == right.x {
      for next in graphemes {
        if next.left.x == x && next.left.offset < next.right.offset {
          return next.left
        }
      }
    }
    let mut advance = 0.0
    let start = left.offset.min(right.offset)
    let end = left.offset.max(right.offset)
    for run in line.runs {
      for glyph in run.glyphs {
        let offset = run.start + glyph.cluster
        if offset >= start && offset < end {
          advance += glyph.advance.to_double() * glyph.scale
        }
      }
    }
    let mut middle = (left.x + right.x) / 2
    let gap = right.x - left.x - advance
    // Extra script spacing moves the stop but not the glyph's hit midpoint.
    if !line.justified &&
      !(start - line.start < line.text.length() &&
      line.text[start - line.start] == 9) &&
      advance > 0 &&
      gap > 0.1 {
      middle += if left.offset < right.offset { -gap / 2 } else { gap / 2 }
    }
    let candidate = if x > middle { right } else { left }
    return if candidate.offset == best.offset && candidate.x == best.x {
      best
    } else {
      candidate
    }
  }
  best
}

///|
/// Affinity selects the correct side of a BiDi or soft-wrap boundary.
pub fn Layout::caret(
  self : Layout,
  paragraph : Int,
  offset : Int,
  affinity : String,
  bidi_level? : Int,
  frame_start? : Int,
) -> Hit raise @failure.Failure {
  guard affinity == "before" || affinity == "after" else {
    @failure.reject("invalid-position", "Invalid caret affinity")
  }
  if bidi_level is Some(level) && (level < 0 || level > 126) {
    @failure.reject("invalid-position", "Invalid cursor direction level")
  }
  if frame_start is Some(start) {
    guard self.frame_caret(paragraph, offset, affinity, start, bidi_level)
      is Some(hit) else {
      @failure.reject(
        "invalid-position", "Position has no adjacent follow frame",
      )
    }
    return self.caret_geometry(hit)
  }
  let mut result : Hit? = None
  for page, frame in self.pages {
    for index, line in frame.lines {
      if line.repeated || line.paragraph != paragraph {
        continue
      }
      for caret in line.carets {
        if caret.offset == offset {
          let hit = self.caret_geometry({
            ..line_hit(line, page, index, caret, affinity),
            bidiLevel: bidi_level,
          })
          if affinity == "before" {
            return hit
          }
          result = Some(hit)
        }
      }
    }
  }
  guard result is Some(hit) else {
    @failure.reject(
      "invalid-position", "Position has no current caret geometry",
    )
  }
  hit
}
