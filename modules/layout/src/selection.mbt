///|
pub(all) struct SelectionRect {
  page : Int
  line : Int
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
  anchor : (Int, Int, String),
  focus : (Int, Int, String),
) -> Array[SelectionRect] raise @failure.Failure {
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
        for image in line.images {
          if image.start != anchor.1.min(focus.1) {
            continue
          }
          let clip = line.clip && image.anchor is None
          let y = if clip { image.y.max(line.y) } else { image.y }
          let bottom = if clip {
            (image.y + image.height).min(line.y + line.height)
          } else {
            image.y + image.height
          }
          if bottom > y {
            selected.push({
              page,
              line: index,
              x: image.x,
              y,
              width: image.width,
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
  let reverse = order[anchor.0] > order[focus.0] ||
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
fn Layout::paragraph_order(self : Layout) -> Map[Int, Int] {
  let order : Map[Int, Int] = Map([])
  for frame in self.pages {
    for line in frame.lines {
      if !order.contains(line.paragraph) {
        order[line.paragraph] = order.length()
      }
    }
  }
  order
}
