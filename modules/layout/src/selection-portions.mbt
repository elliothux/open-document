///|
priv struct SelectionBox {
  left : Int
  top : Int
  right : Int
  bottom : Int
} derive(Eq)

///|
priv struct SelectionEndpoint {
  rect : SelectionBox
  line : SelectionBox
  outer : SelectionBox?
  inner : SelectionBox?
}

///|
fn selection_twips(value : Double) -> Int {
  (value * 20).round().to_int()
}

///|
fn Line::selection_portion(
  self : Line,
  start : Int,
  end : Int,
  fonts : Array[FontInfo],
) -> SelectionBox {
  let mut left = 1.0 / 0.0
  let mut right = -1.0 / 0.0
  let mut ascent = 0.0
  let mut descent = 0.0
  let mut baseline = self.y
  for i = 0; i + 1 < self.carets.length(); i = i + 1 {
    let a = self.carets[i]
    let b = self.carets[i + 1]
    if start <= a.offset && b.offset <= end {
      left = left.min(a.after.min(b.before))
      right = right.max(a.after.max(b.before))
    }
  }
  for run in self.runs {
    for glyph in run.glyphs {
      let offset = run.start + glyph.cluster
      if start <= offset && offset < end {
        let font = fonts[glyph.font]
        let (a, d) = scaled_line_metrics(
          font.ascent,
          font.descent,
          font.upem,
          glyph.scale * font.upem.to_double(),
        )
        ascent = ascent.max(a)
        descent = descent.max(d)
        baseline = run.baseline
      }
    }
  }
  {
    left: selection_twips(left),
    right: selection_twips(right),
    top: selection_twips(baseline - ascent),
    bottom: selection_twips(baseline + descent),
  }
}

///|
fn Line::selection_endpoint(
  self : Line,
  offset : Int,
  fonts : Array[FontInfo],
) -> SelectionEndpoint {
  let line = {
    left: selection_twips(self.areaX),
    right: selection_twips(self.areaX + self.areaWidth),
    top: selection_twips(self.y),
    bottom: selection_twips(self.y + self.height),
  }
  let mut outer = None
  let mut inner = None
  let maximum = self
    .bidi_ranges()
    .iter()
    .fold(init=self.baseLevel, (level, range) => level.max(range.2))
  // Writer stops before a portion whose logical start equals the endpoint.
  for (start, end) in self.bidi_portions(self.baseLevel + 1) {
    if start < offset && offset < end {
      outer = Some(self.selection_portion(start, end, fonts))
      // Writer's recursive cursor query retains the deepest nested portion.
      for depth = self.baseLevel + 2; depth <= maximum; depth = depth + 1 {
        for (a, b) in self.bidi_portions(depth) {
          if start <= a && b <= end && a < offset && offset < b {
            inner = Some(self.selection_portion(a, b, fonts))
          }
        }
      }
      break
    }
  }
  let mut x = self.x
  for caret in self.carets {
    if caret.offset == offset {
      x = caret.after
      break
    }
  }
  x = self.bidi_caret_x(offset, self.baseLevel, x)
  let portion = match inner {
    Some(box) => box
    None => outer.unwrap_or(line)
  }
  let top = portion.top
  let bottom = portion.bottom
  let x = selection_twips(x)
  { rect: { left: x, right: x + 1, top, bottom, }, line, outer, inner, }
}

///|
fn selection_clip(box : SelectionBox, frame : SelectionBox) -> SelectionBox {
  {
    left: box.left.max(frame.left),
    top: box.top.max(frame.top),
    right: box.right.min(frame.right),
    bottom: box.bottom.min(frame.bottom),
  }
}

///|
fn selection_piece(
  pieces : Array[SelectionBox],
  box : SelectionBox,
  frame : SelectionBox,
) -> Unit {
  let box = selection_clip(box, frame)
  if box.right - box.left > 1 && box.bottom - box.top > 1 {
    pieces.push(box)
  }
}

///|
fn selection_end_pieces(
  endpoint : SelectionEndpoint,
  other : SelectionEndpoint,
  start : Bool,
  rtl : Bool,
  pieces : Array[SelectionBox],
  frame : SelectionBox,
) -> SelectionBox {
  guard endpoint.outer is Some(outer) else { return endpoint.rect }
  let mut box = endpoint.rect
  if endpoint.inner is Some(inner) {
    let tail = if start {
      { ..outer, right: inner.left, }
    } else {
      { ..outer, left: inner.right, }
    }
    if endpoint.outer != other.outer {
      selection_piece(pieces, tail, frame)
    }
    box = if start {
      { ..box, right: inner.right, }
    } else {
      { ..box, left: inner.left, }
    }
  } else {
    box = if start != rtl {
      { ..box, left: outer.left, }
    } else {
      { ..box, right: outer.right, }
    }
  }
  if start && box.top == outer.top {
    box = { ..box, top: endpoint.line.top, }
  }
  if !start && box.bottom == outer.bottom {
    box = { ..box, bottom: endpoint.line.bottom, }
  }
  selection_piece(pieces, box, frame)
  if start && endpoint.rect.bottom < endpoint.line.bottom {
    let mut tail = { ..box, top: box.bottom, bottom: endpoint.line.bottom, }
    if endpoint.rect.bottom < outer.bottom {
      tail = if !rtl {
        { ..tail, right: outer.right, }
      } else {
        { ..tail, left: outer.left, }
      }
    }
    selection_piece(pieces, tail, frame)
  }
  if !start && endpoint.rect.top != endpoint.line.top {
    let mut tail = { ..box, bottom: box.top, top: endpoint.line.top, }
    if endpoint.rect.top != outer.top {
      tail = if !rtl {
        { ..tail, left: outer.left, }
      } else {
        { ..tail, right: outer.right, }
      }
    }
    selection_piece(pieces, tail, frame)
  }
  let x = if start != rtl { outer.right } else { outer.left }
  { ..endpoint.line, left: x, right: x + 1, }
}

///|
fn selection_boxes(
  start : SelectionEndpoint,
  end : SelectionEndpoint,
  rtl : Bool,
  frame : SelectionBox,
  starts : Bool,
  ends : Bool,
) -> Array[SelectionBox] {
  let pieces = []
  // Writer fills each page frame directly, without synthetic last-line cuts.
  if !starts || !ends {
    if starts {
      let a = selection_end_pieces(start, end, true, rtl, pieces, frame)
      selection_piece(
        pieces,
        if rtl {
          { ..a, left: frame.left, }
        } else {
          { ..a, right: frame.right, }
        },
        frame,
      )
      selection_piece(pieces, { ..frame, top: a.bottom, }, frame)
    } else if ends {
      let b = selection_end_pieces(end, start, false, rtl, pieces, frame)
      selection_piece(pieces, { ..frame, bottom: b.top, }, frame)
      selection_piece(
        pieces,
        if rtl {
          { ..b, left: b.left.min(frame.right - 2), right: frame.right, }
        } else {
          { ..b, left: frame.left, right: b.right.max(frame.left + 2), }
        },
        frame,
      )
    } else {
      selection_piece(pieces, frame, frame)
    }
    return pieces
  }
  let mut a = start.rect
  let mut b = end.rect
  if start.outer != end.outer {
    a = selection_end_pieces(start, end, true, rtl, pieces, frame)
    b = selection_end_pieces(end, start, false, rtl, pieces, frame)
  } else if start.outer is Some(_) && start.inner != end.inner {
    if start.inner is Some(inner) {
      selection_piece(pieces, { ..a, right: inner.right, }, frame)
      let x = if rtl { inner.right } else { inner.left }
      a = { ..start.line, left: x, right: x + 1, }
    }
    if end.inner is Some(inner) {
      selection_piece(pieces, { ..b, left: inner.left, }, frame)
      let x = if rtl { inner.left } else { inner.right }
      b = { ..end.line, left: x, right: x + 1, }
    }
  }
  if (start.outer is Some(_) && start.outer == end.outer) || a.top == b.top {
    selection_piece(
      pieces,
      {
        left: a.left.min(b.right - 1),
        right: (a.left.max(b.right - 1) + 1).max(a.left.min(b.right - 1) + 2),
        top: a.top.min(b.bottom - 1),
        bottom: a.top.max(b.bottom - 1) + 1,
      },
      frame,
    )
  } else {
    selection_piece(
      pieces,
      if rtl {
        { ..a, left: frame.left, }
      } else {
        { ..a, right: frame.right, }
      },
      frame,
    )
    if a.bottom != b.top {
      selection_piece(
        pieces,
        { ..frame, top: a.bottom.min(b.top), bottom: a.bottom.max(b.top), },
        frame,
      )
    }
    selection_piece(
      pieces,
      if rtl {
        { ..b, right: frame.right, }
      } else {
        { ..b, left: frame.left, }
      },
      frame,
    )
  }
  pieces
}

///|
fn Layout::portion_selection(
  self : Layout,
  start : Hit,
  end : Hit,
) -> Array[SelectionRect] {
  let first = self.pages[start.page].lines[start.line]
  let last = self.pages[end.page].lines[end.line]
  let order = self.paragraph_order()
  let rects = []
  for page in start.page..<=end.page {
    let frame = self.pages[page]
    let ranks = frame.lines.map(line => order[line.paragraph])
    ranks.sort()
    let mut previous = -1
    for rank in ranks {
      if rank == previous ||
        rank < order[start.paragraph] ||
        rank > order[end.paragraph] {
        continue
      }
      previous = rank
      let lines = frame.lines.filter(line => order[line.paragraph] == rank)
      guard lines.get(0) is Some(top) && lines.last() is Some(bottom) else {
        continue
      }
      let paragraph = top.paragraph
      let starts = page == start.page && paragraph == start.paragraph
      let ends = page == end.page && paragraph == end.paragraph
      let bounds = {
        left: lines
        .iter()
        .fold(init=selection_twips(top.areaX), (value, line) => {
          value.min(selection_twips(line.areaX))
        }),
        right: lines
        .iter()
        .fold(init=selection_twips(top.areaX + top.areaWidth), (value, line) => {
          value.max(selection_twips(line.areaX + line.areaWidth))
        }),
        top: selection_twips(top.y),
        bottom: selection_twips(bottom.y + bottom.height),
      }
      let a = if starts {
        first.selection_endpoint(start.offset, self.fonts)
      } else {
        let endpoint = top.selection_endpoint(top.start, self.fonts)
        let x = if top.baseLevel % 2 == 0 { bounds.left } else { bounds.right }
        {
          ..endpoint,
          rect: { ..endpoint.line, left: x, right: x + 1, },
          outer: None,
          inner: None,
        }
      }
      let b = if ends {
        last.selection_endpoint(end.offset, self.fonts)
      } else {
        let endpoint = bottom.selection_endpoint(bottom.end, self.fonts)
        let x = if bottom.baseLevel % 2 == 0 {
          bounds.right
        } else {
          bounds.left
        }
        {
          ..endpoint,
          rect: { ..endpoint.line, left: x, right: x + 1, },
          outer: None,
          inner: None,
        }
      }
      let a = { ..a, rect: selection_clip(a.rect, bounds), }
      let b = { ..b, rect: selection_clip(b.rect, bounds), }
      let pieces = selection_boxes(
        a,
        b,
        top.baseLevel % 2 != 0,
        bounds,
        starts,
        ends,
      )
      let cuts = pieces
        .iter()
        .flat_map(box => [box.top, box.bottom].iter())
        .collect()
      cuts.sort()
      for i = 0; i + 1 < cuts.length(); i = i + 1 {
        let y = cuts[i]
        let bottom = cuts[i + 1]
        if bottom <= y {
          continue
        }
        let intervals = pieces.filter(box => {
          box.top <= y && bottom <= box.bottom
        })
        intervals.sort_by((a, b) => a.left.compare(b.left))
        let merged : Array[SelectionBox] = []
        for box in intervals {
          if merged.last() is Some(previous) && box.left <= previous.right {
            merged[merged.length() - 1] = {
              ..previous,
              right: previous.right.max(box.right),
            }
          } else {
            merged.push(box)
          }
        }
        let mut line_index = 0
        for index, line in frame.lines {
          if line.paragraph == paragraph && selection_twips(line.y) <= y {
            line_index = index
          }
        }
        for box in merged {
          let shaped_right = box.right == bounds.right ||
            frame.lines
            .iter()
            .any(line => {
              line.paragraph == paragraph &&
              line.carets
              .iter()
              .any(caret => {
                selection_twips(caret.before) == box.right ||
                selection_twips(caret.after) == box.right
              })
            })
          let line = frame.lines[line_index]
          let whole_line = y == selection_twips(line.y) &&
            bottom == selection_twips(line.y + line.height)
          rects.push({
            page,
            line: line_index,
            x: box.left.to_double() / 20,
            y: y.to_double() / 20,
            width: (box.right - box.left - (if shaped_right { 0 } else { 1 })).to_double() /
            20,
            height: if whole_line {
              line.height
            } else {
              (bottom - y - 1).to_double() / 20
            },
          })
        }
      }
    }
  }
  rects
}
