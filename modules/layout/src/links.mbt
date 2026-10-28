///|
pub(all) enum LinkTarget {
  External(String)
  Internal(Int32, Double, Double)
}

///|
pub(all) struct PageLink {
  rect : SelectionRect
  target : LinkTarget
}

///|
/// Resolve only the visible text edges, without selection's trailing line fill.
pub fn Line::link_rects(
  self : Line,
  start : Int32,
  end : Int32,
) -> Array[Border] {
  let intervals : Array[(Double, Double)] = []
  for i = 0; i + 1 < self.carets.length(); i = i + 1 {
    let a = self.carets[i]
    let b = self.carets[i + 1]
    if start <= a.offset && b.offset <= end {
      intervals.push((a.after.min(b.before), a.after.max(b.before)))
    }
  }
  intervals.sort_by((a, b) => a.0.compare(b.0))
  let rects : Array[Border] = []
  for (left, right) in intervals {
    let clip = self.cellClip
    let x = clip.map(c => left.max(c.x)).unwrap_or(left)
    let y = clip.map(c => self.y.max(c.y)).unwrap_or(self.y)
    let edge = clip.map(c => right.min(c.x + c.width)).unwrap_or(right)
    let bottom = clip
      .map(c => (self.y + self.height).min(c.y + c.height))
      .unwrap_or(self.y + self.height)
    if edge <= x || bottom <= y {
      continue
    }
    if rects.last() is Some(previous) && x <= previous.x + previous.width {
      rects[rects.length() - 1] = {
        ..previous,
        width: edge.max(previous.x + previous.width) - previous.x,
      }
    } else {
      rects.push({ x, y, width: edge - x, height: bottom - y, })
    }
  }
  rects
}
