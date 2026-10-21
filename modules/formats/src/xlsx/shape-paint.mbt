///|
fn SheetShape::font_key(self : SheetShape) -> String {
  self.font +
  (if self.bold { "|bold" } else { "" }) +
  (if self.italic { "|italic" } else { "" })
}

///|
fn SheetObject::paint_bounds(
  self : SheetObject,
  rect : @layout.Border,
) -> @layout.Border {
  let pen = self.shape
    .map(shape => {
      if shape.stroke.is_empty() {
        0.0
      } else {
        shape.line_width / 2
      }
    })
    .unwrap_or(0)
  {
    x: rect.x - pen,
    y: rect.y - pen,
    width: rect.width + pen * 2,
    height: rect.height + pen * 2,
  }
}

///|
fn SheetShape::paint(
  self : SheetShape,
  primitives : Array[@layout.PositionedPrimitive],
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  if rect.width < 0 || rect.height < 0 {
    return
  }
  primitives.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: rect.x, f: rect.y, }))
  primitives.push(
    Path(
      @layout.basic_shape_path(self.preset, rect.width, rect.height),
      self.fill,
      self.stroke,
      self.line_width,
      { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 10, },
    ),
  )
  let width = rect.width - self.left - self.right
  let height = rect.height - self.top - self.bottom
  if !self.text.is_empty() && width > 0 && height > 0 {
    let block = probe.text_block(
      self.text,
      @layout.TextStyle::new(self.font_key(), self.size, self.color),
      profile,
      width,
      self.wrap,
    )
    let dy = self.top +
      (if self.vertical == "center" {
        (height - block.height).max(0) / 2
      } else if self.vertical == "bottom" {
        (height - block.height).max(0)
      } else {
        0.0
      })
    primitives.push(Clip({ x: self.left, y: self.top, width, height, }))
    for index, line in block.lines {
      let dx = self.left +
        (if self.align == "center" {
          (width - block.widths[index]).max(0) / 2
        } else if self.align == "right" {
          (width - block.widths[index]).max(0)
        } else {
          0.0
        })
      primitives.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: dx, f: dy, }))
      primitives.append(line)
      primitives.push(Restore)
    }
    primitives.push(Restore)
  }
  primitives.push(Restore)
}
