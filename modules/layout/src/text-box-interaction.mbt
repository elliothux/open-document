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
fn Layout::text_box_layout(self : Layout, paragraph : Int) -> Layout? {
  for page, frame in self.pages {
    for line in frame.lines {
      for drawing in line.drawings {
        if drawing.content is TextBox(_, text) &&
          text.paragraphs.any(p => p.id == paragraph) {
          let lines = drawing.text_lines()
          // Use the existing caret, bidi, range and navigation algorithms on this story.
          return Some({
            ..self,
            pages: self.pages.mapi((index, source) => {
              ..source,
              lines: if index == page {
                lines
              } else {
                []
              },
              cellAreas: [],
            }),
            running: self.running.map(_ => []),
          })
        }
      }
    }
  }
  None
}

///|
fn Layout::text_box_hit(
  self : Layout,
  drawing : PlacedDrawingFrame,
  page : Int,
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
