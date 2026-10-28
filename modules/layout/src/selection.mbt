///|
pub(all) struct SelectionRect {
  page : Int32
  line : Int32
  x : Double
  y : Double
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend SelectionRect with ToJson::{to_json}

///|
/// Highlights logical graphemes using their shaped visual edges, without mutation.
pub fn Layout::selection_rects(
  self : Layout,
  anchor : (Int32, Int32, String),
  focus : (Int32, Int32, String),
) -> Array[SelectionRect] raise @failure.Failure {
  if self.text_box_layout(anchor.0) is Some(story) {
    return story.selection_rects(anchor, focus)
  }
  let anchor_hit = self.caret(anchor.0, anchor.1, anchor.2)
  let focus_hit = self.caret(focus.0, focus.1, focus.2)
  if anchor.0 == focus.0 && anchor.1 == focus.1 {
    return []
  }
  if anchor.0 == focus.0 && (anchor.1 - focus.1).abs() == 1 {
    let selected : Array[SelectionRect] = []
    for page, frame in self.pages {
      for index, line in frame.lines {
        if line.paragraph != anchor.0 || line.repeated {
          continue
        }
        for image in line.drawings {
          if image.start != anchor.1.min(focus.1) {
            continue
          }
          let clip = line.clip && image.anchor is None
          let (x, top, width, height) = image.interaction_bounds()
          let y = if clip { top.max(line.y) } else { top }
          let bottom = if clip {
            (top + height).min(line.y + line.height)
          } else {
            top + height
          }
          if bottom > y {
            selected.push({
              page,
              line: index,
              x,
              y,
              width,
              height: bottom - y,
            })
          }
        }
      }
    }
    if !selected.is_empty() {
      return self.clip_cell_selection(selected)
    }
  }
  let order = self.paragraph_order()
  guard order.get(anchor.0) is Some(anchor_order) &&
    order.get(focus.0) is Some(focus_order) else {
    @failure.reject("invalid-position", "Selection crosses text stories")
  }
  let reverse = anchor_order > focus_order ||
    (anchor.0 == focus.0 && anchor.1 > focus.1)
  let start = if reverse { focus } else { anchor }
  let end = if reverse { anchor } else { focus }
  let end_hit = if reverse { anchor_hit } else { focus_hit }
  let first = order[start.0]
  let last = order[end.0]
  if (anchor.0 != focus.0 || anchor.1 != focus.1) &&
    (
      (anchor.0 == focus.0 && anchor_hit.page != focus_hit.page) ||
      self.pages
      .iter()
      .any(page => {
        page.lines
        .iter()
        .any(line => {
          first <= order[line.paragraph] &&
          order[line.paragraph] <= last &&
          line.bidi_ranges().iter().any(range => range.2 > line.baseLevel)
        })
      })
    ) {
    return self.clip_cell_selection(
      if !reverse {
        self.portion_selection(anchor_hit, focus_hit)
      } else {
        self.portion_selection(focus_hit, anchor_hit)
      },
    )
  }
  let rects : Array[SelectionRect] = []
  for page, frame in self.pages {
    for index, line in frame.lines {
      if line.repeated {
        continue
      }
      let rank = order[line.paragraph]
      if rank < first || rank > last {
        continue
      }
      let low = if line.paragraph == start.0 { start.1 } else { line.start }
      let high = if line.paragraph == end.0 { end.1 } else { line.end }
      let intervals : Array[(Double, Double)] = []
      for i = 0; i + 1 < line.carets.length(); i = i + 1 {
        let a = line.carets[i]
        let b = line.carets[i + 1]
        if a.offset >= low && b.offset <= high {
          intervals.push((a.after.min(b.before), a.after.max(b.before)))
        }
      }
      let continues = rank < last ||
        end_hit.page > page ||
        (end_hit.page == page && end_hit.line > index)
      if continues && !intervals.is_empty() {
        let rtl = line.baseLevel % 2 != 0
        let mut edge = if rtl {
          line.areaX + line.areaWidth
        } else {
          line.areaX
        }
        for caret in line.carets {
          edge = if rtl {
            edge.min(caret.before.min(caret.after))
          } else {
            edge.max(caret.before.max(caret.after))
          }
        }
        if rtl {
          intervals.push((line.areaX, edge.max(line.areaX)))
        } else {
          intervals.push(
            (edge.min(line.areaX + line.areaWidth), line.areaX + line.areaWidth),
          )
        }
      }
      intervals.sort_by((a, b) => {
        if a.0 == b.0 {
          a.1.compare(b.1)
        } else {
          a.0.compare(b.0)
        }
      })
      for (left, right) in intervals {
        if rects.last() is Some(previous) &&
          previous.page == page &&
          previous.line == index &&
          left <= previous.x + previous.width {
          rects[rects.length() - 1] = {
            ..previous,
            width: right.max(previous.x + previous.width) - previous.x,
          }
        } else {
          rects.push({
            page,
            line: index,
            x: left,
            y: line.y,
            width: right - left,
            height: line.height,
          })
        }
      }
    }
  }
  self.clip_cell_selection(rects)
}

///|
fn Layout::clip_cell_selection(
  self : Layout,
  rects : Array[SelectionRect],
) -> Array[SelectionRect] {
  rects.filter_map(rect => {
    let line = self.pages[rect.page].lines[rect.line]
    guard line.cellClip is Some(clip) else { return Some(rect) }
    let x = rect.x.max(clip.x)
    let y = rect.y.max(clip.y)
    let width = (rect.x + rect.width).min(clip.x + clip.width) - x
    let height = (rect.y + rect.height).min(clip.y + clip.height) - y
    if width > 0 && height > 0 {
      Some({ ..rect, x, y, width, height, })
    } else {
      None
    }
  })
}

///|
fn Layout::paragraph_order(self : Layout) -> Map[Int32, Int32] {
  let order : Map[Int32, Int32] = Map([])
  for frame in self.pages {
    for line in frame.lines {
      if !order.contains(line.paragraph) {
        order[line.paragraph] = order.length()
      }
    }
  }
  order
}
