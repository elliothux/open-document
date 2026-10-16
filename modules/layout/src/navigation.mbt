///|
priv struct VisualGrapheme {
  left : Hit
  right : Hit
}

///|
fn Line::visual_graphemes(
  self : Line,
  page : Int,
  index : Int,
) -> Array[VisualGrapheme] {
  let levels = self.bidi_ranges()
  let graphemes : Array[VisualGrapheme] = []
  let mut run = 0
  for i = 0; i + 1 < self.carets.length(); i = i + 1 {
    let a = self.carets[i]
    let b = self.carets[i + 1]
    while run < levels.length() && levels[run].1 <= a.offset {
      run += 1
    }
    let level = if run < levels.length() && levels[run].0 <= a.offset {
      levels[run].2
    } else {
      self.baseLevel
    }
    let start = line_hit(self, page, index, a, "after")
    let end = line_hit(self, page, index, b, "before")
    let rtl = start.x > end.x || (start.x == end.x && level % 2 != 0)
    graphemes.push({
      left: if rtl {
        end
      } else {
        start
      },
      right: if rtl {
        start
      } else {
        end
      },
    })
  }
  graphemes
}

///|
fn horizontal_step(
  line : Line,
  page : Int,
  index : Int,
  offset : Int,
  right : Bool,
) -> Hit? {
  let mut best : Hit? = None
  for caret in line.carets {
    if right && caret.offset > offset {
      return Some(line_hit(line, page, index, caret, "before"))
    }
    if !right && caret.offset < offset {
      best = Some(line_hit(line, page, index, caret, "after"))
    }
  }
  best
}

///|
/// Compares logical positions in the current layout's paragraph order.
pub fn Layout::compare_positions(
  self : Layout,
  a : (Int, Int),
  b : (Int, Int),
) -> Int raise @failure.Failure {
  ignore(self.caret(a.0, a.1, "after"))
  ignore(self.caret(b.0, b.1, "after"))
  if a.0 == b.0 {
    return a.1.compare(b.1)
  }
  let order = self.paragraph_order()
  order[a.0].compare(order[b.0])
}

///|
/// Moves on final geometry only; the DOCX session owns selection and preferred x.
pub fn Layout::move_caret(
  self : Layout,
  position : (Int, Int, String),
  direction : String,
  goal_x? : Double,
  bidi_level? : Int,
  frame_start? : Int,
) -> Hit raise @failure.Failure {
  self.caret_geometry(
    self.navigate(position, direction, goal_x?, bidi_level?, frame_start?),
  )
}

///|
fn Layout::horizontal_hit(
  self : Layout,
  origin : Hit,
  target : Hit,
  right : Bool,
) -> Hit raise @failure.Failure {
  if origin.paragraph != target.paragraph {
    return target
  }
  let origin_line = self.pages[origin.page].lines[origin.line]
  let target_line = self.pages[target.page].lines[target.line]
  let crossed = if right && origin.offset < origin_line.start {
    let logical = self.caret(origin.paragraph, origin.offset, "after")
    self.pages[logical.page].lines[logical.line]
  } else if right && origin.offset < origin_line.end {
    origin_line
  } else {
    target_line
  }
  let level = crossed.bidi_level(
    if right {
      origin.offset
    } else {
      target.offset
    },
    "after",
  )
  if !right &&
    origin.page > target.page &&
    origin.offset == origin_line.start &&
    target_line.end == origin.offset &&
    self.frame_caret(
      target.paragraph,
      target.offset,
      target.affinity,
      origin_line.start,
      Some(level),
    )
    is Some(hit) {
    return hit
  }
  let target = if right &&
    (target.offset == target_line.end || target.offset == target_line.start) {
    let next = self.caret(
      target.paragraph,
      target.offset,
      "after",
      bidi_level=level,
    )
    if next.page != target.page ||
      next.line != target.line ||
      target.offset == target_line.start {
      next
    } else {
      target
    }
  } else {
    target
  }
  let line = self.pages[target.page].lines[target.line]
  {
    ..target,
    bidiLevel: if level == line.bidi_level(target.offset, target.affinity) {
      None
    } else {
      Some(level)
    },
  }
}

///|
fn Layout::navigate(
  self : Layout,
  position : (Int, Int, String),
  direction : String,
  goal_x? : Double,
  bidi_level? : Int,
  frame_start? : Int,
) -> Hit raise @failure.Failure {
  guard ["left", "right", "up", "down", "home", "end"].contains(direction) else {
    @failure.reject("invalid-operation", "Unknown navigation direction")
  }
  let origin = self.caret(
    position.0,
    position.1,
    position.2,
    bidi_level?,
    frame_start?,
  )
  let line = self.pages[origin.page].lines[origin.line]
  if direction == "home" || direction == "end" {
    let start = direction == "home"
    let hit = line_hit(
      line,
      origin.page,
      origin.line,
      if start {
        line.carets[0]
      } else {
        line.carets.last().unwrap()
      },
      if start {
        "after"
      } else {
        "before"
      },
    )
    let hit = if !start {
      let next = self.caret(
        hit.paragraph,
        hit.offset,
        "after",
        bidi_level=line.baseLevel,
      )
      // Writer resolves a paragraph's frame-end offset on the following page.
      if next.page != hit.page {
        next
      } else {
        hit
      }
    } else {
      hit
    }
    let target_line = self.pages[hit.page].lines[hit.line]
    return {
      ..hit,
      bidiLevel: if line.baseLevel ==
        target_line.bidi_level(hit.offset, hit.affinity) {
        None
      } else {
        Some(line.baseLevel)
      },
    }
  }
  if direction == "left" || direction == "right" {
    let right = direction == "right"
    if horizontal_step(line, origin.page, origin.line, origin.offset, right)
      is Some(hit) {
      return self.horizontal_hit(origin, hit, right)
    }
    let forward = right
    let mut adjacent : Hit? = None
    let mut found = false
    for page, frame in self.pages {
      for index, candidate in frame.lines {
        if candidate.repeated {
          continue
        }
        if page == origin.page && index == origin.line {
          found = true
          if !forward {
            break
          }
        } else if !candidate.carets.is_empty() && (!forward || found) {
          let entry = if candidate.paragraph == line.paragraph {
            horizontal_step(candidate, page, index, origin.offset, right)
          } else {
            Some(
              line_hit(
                candidate,
                page,
                index,
                if forward {
                  candidate.carets[0]
                } else {
                  candidate.carets.last().unwrap()
                },
                if forward {
                  "after"
                } else {
                  "before"
                },
              ),
            )
          }
          if entry is Some(_) {
            adjacent = entry
            if forward {
              break
            }
          }
        }
      }
      if (forward && adjacent is Some(_)) || (!forward && found) {
        break
      }
    }
    match adjacent {
      Some(hit) => self.horizontal_hit(origin, hit, right)
      None => origin
    }
  } else {
    let x = goal_x.unwrap_or(origin.x)
    guard x > -1.0 / 0.0 && x < 1.0 / 0.0 else {
      @failure.reject("invalid-position", "Vertical target x must be finite")
    }
    let mut origin_y = if line.cellClip is Some(_) { origin.y } else { line.y }
    for page = 0; page < origin.page; page = page + 1 {
      origin_y += self.pages[page].height
    }
    let down = direction == "down"
    let mut top = 0.0
    let mut chosen : (Int, Int)? = None
    let mut same_cell = false
    let mut vertical = 1.0 / 0.0
    let mut horizontal = 1.0 / 0.0
    for page, frame in self.pages {
      for index, candidate in frame.lines {
        if candidate.repeated {
          continue
        }
        if candidate.cellClip is Some(rect) &&
          (
            candidate.y >= rect.y + rect.height ||
            candidate.y + candidate.height <= rect.y
          ) {
          continue
        }
        if candidate.carets.is_empty() {
          continue
        }
        if line.container != 0 &&
          candidate.areaX.max(line.areaX) >=
          (candidate.areaX + candidate.areaWidth).min(
            line.areaX + line.areaWidth,
          ) {
          continue
        }
        let y = top + candidate.y
        let dy = if down { y - origin_y } else { origin_y - y }
        if dy <= 0 {
          continue
        }
        let cell = line.container != 0 && line.container == candidate.container
        let dx = (candidate.areaX - x).max(0) +
          (x - candidate.areaX - candidate.areaWidth).max(0)
        if (cell && !same_cell) ||
          (
            cell == same_cell &&
            (dy < vertical || (dy == vertical && dx < horizontal))
          ) {
          chosen = Some((page, index))
          same_cell = cell
          vertical = dy
          horizontal = dx
        }
      }
      top += frame.height
    }
    match chosen {
      Some((page, index)) =>
        nearest_caret(self.pages[page].lines[index], page, index, x)
      None => origin
    }
  }
}
