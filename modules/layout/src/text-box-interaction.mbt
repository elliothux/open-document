///|
/// Returns laid-out text box lines in page coordinates, with the frame's text clip.
pub fn PlacedDrawingFrame::text_lines(self : PlacedDrawingFrame) -> Array[Line] {
  guard self.content is TextBox(_, text) else { return [] }
  text.lines.map(line => {
    ..line,
    x: line.x + self.x,
    y: line.y + self.y,
    areaX: line.areaX + self.x,
    bars: line.bars.map(x => x + self.x),
    carets: line.carets.map(c => {
      ..c,
      before: c.before + self.x,
      after: c.after + self.x,
    }),
    runs: line.runs.map(run => {
      ..run,
      x: run.x + self.x,
      baseline: run.baseline + self.y,
    }),
    cellClip: if text.clip {
      Some({ x: self.x, y: self.y, width: self.width, height: self.height, })
    } else {
      None
    },
  })
}

///|
fn Layout::text_box_layout(self : Layout, paragraph : Int32) -> Layout? {
  let mut found = false
  let pages = self.pages.map(frame => {
    let lines : Array[Line] = []
    for
      drawing in text_box_reading_order(
        frame.lines.map(line => line.drawings).flatten(),
      ) {
      if drawing.content is TextBox(_, text) &&
        text.paragraphs.any(p => p.id == paragraph) {
        found = true
        lines.append(drawing.text_lines())
      }
    }
    { ..frame, lines, cellAreas: [], }
  })
  if !found {
    return None
  }
  Some({
    ..self,
    pages,
    running: self.running.map(frame => {
      ..frame,
      lines: [],
      borders: [],
      fills: [],
      pageBorders: [],
      cellAreas: [],
    }),
  })
}

///|
fn text_box_reading_order(
  drawings : Array[PlacedDrawingFrame],
) -> Array[PlacedDrawingFrame] {
  let groups : Map[Int32, Array[(Int32, PlacedDrawingFrame)]] = Map([])
  for drawing in drawings {
    if drawing.content is TextBox(_, text) && !text.flowFrames.is_empty() {
      groups
      .get_or_init(text.paragraphs[0].id, () => [])
      .push((text.flowFrames.length(), drawing))
    }
  }
  for group in groups.values() {
    group.sort_by((a, b) => a.0.compare(b.0))
  }
  let indices : Map[Int32, Int32] = Map([])
  drawings.map(drawing => {
    if drawing.content is TextBox(_, text) && !text.flowFrames.is_empty() {
      let key = text.paragraphs[0].id
      let index = indices.get(key).unwrap_or(0)
      indices[key] = index + 1
      groups[key][index].1
    } else {
      drawing
    }
  })
}

///|
fn Layout::text_box_hit(
  self : Layout,
  drawing : PlacedDrawingFrame,
  page : Int32,
  x : Double,
  y : Double,
) -> Hit? raise @failure.Failure {
  guard drawing.content is TextBox(_, text) else { return None }
  // Keep a frame border available for whole-object selection and dragging.
  let left = drawing.x + text.insets[3].max(3)
  let top = drawing.y + text.insets[0].max(3)
  let right = drawing.x + drawing.width - text.insets[1].max(3)
  let bottom = drawing.y + drawing.height - text.insets[2].max(3)
  guard x >= left && x <= right && y >= top && y <= bottom else { return None }
  let story = self.text_box_layout(text.paragraphs[0].id).unwrap()
  Some(story.hit_test(page, x, y))
}
