///|
fn Border::intersect(self : Border, other : Border) -> Border? {
  let x = self.x.max(other.x)
  let y = self.y.max(other.y)
  let right = (self.x + self.width).min(other.x + other.width)
  let bottom = (self.y + self.height).min(other.y + other.height)
  if right < x || bottom < y {
    None
  } else {
    Some({ x, y, width: right - x, height: bottom - y, })
  }
}

///|
fn PageFrame::clipped_to(self : PageFrame, clip : Border) -> PageFrame {
  {
    ..self,
    lines: self.lines.map(line => {
      ..line,
      cellClip: Some(
        line.cellClip
        .map(rect => {
          rect.intersect(clip).unwrap_or({ ..clip, width: 0, height: 0, })
        })
        .unwrap_or(clip),
      ),
    }),
    fills: self.fills.filter_map(fill => {
      (
        { x: fill.x, y: fill.y, width: fill.width, height: fill.height, } :
        Border)
      .intersect(clip)
      .map(rect => {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        color: fill.color,
      })
    }),
    borders: self.borders.filter_map(stroke => {
      stroke.rect.intersect(clip).map(rect => { ..stroke, rect, })
    }),
    cellAreas: self.cellAreas.filter_map(area => {
      (
        { x: area.x, y: area.y, width: area.width, height: area.height, } :
        Border)
      .intersect(clip)
      .map(rect => {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        paragraphs: area.paragraphs.copy(),
      })
    }),
  }
}
