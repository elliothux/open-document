///|
fn Line::shifted(self : Line, x : Double, y : Double) -> Line {
  {
    ..self.copy_geometry(),
    x: self.x + x,
    y: self.y + y,
    areaX: self.areaX + x,
    bars: self.bars.map(v => v + x),
    cellClip: self.cellClip.map(rect => {
      ..rect,
      x: rect.x + x,
      y: rect.y + y,
    }),
    runs: self.runs.map(run => {
      ..run.copy_geometry(),
      x: run.x + x,
      baseline: run.baseline + y,
    }),
    marker: self.marker.map(run => {
      ..run.copy_geometry(),
      x: run.x + x,
      baseline: run.baseline + y,
    }),
    carets: self.carets.map(c => {
      ..c,
      before: c.before + x,
      after: c.after + x,
    }),
    drawings: self.drawings.map(d => {
      ..d,
      x: d.x + x,
      y: d.y + y,
      content: d.content.copy(),
    }),
  }
}

///|
fn Pagination::paragraph_frame(
  self : Pagination,
  frame : ParagraphFrame,
  blocks : Array[BodyBlock],
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  guard !blocks.is_empty() &&
    blocks.length() <= 32768 &&
    [frame.width, frame.height, frame.horizontalSpace, frame.verticalSpace].all(v => {
        v >= 0 && v <= 14400 && !v.is_nan()
      },
    ) else {
    @failure.reject("invalid-style", "Invalid paragraph frame bounds")
  }
  if blocks[0] is BodyParagraph({ pageBreakBefore: true, .. }) &&
    !self.pages.last().unwrap().lines.is_empty() {
    self.sheet_break()
  }
  let available = self.page.width - self.page.left - self.page.right
  let mut width = if frame.width > 0 { frame.width } else { available }
  let area = Pagination::new({
    width,
    height: 14400,
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
  })
  let mut first_border = true
  for block in blocks {
    if block is BodyParagraph(p) {
      guard !p.spans.any(s => {
          s.drawing.bind(d => d.anchor) is Some(_) ||
          s.field.has_prefix("NOTE:")
        }) &&
        !paragraph_has_break(p) else {
        @failure.reject(
          "unsupported-layout", "Anchored drawings or breaks inside paragraph frames require flow support",
        )
      }
      guard p.frame.map(f => Json(f.borders)) == Some(Json(frame.borders)) else {
        @failure.reject(
          "unsupported-layout", "Mixed border groups inside a paragraph frame require border grouping support",
        )
      }
      if first_border &&
        p.frame.bind(f => f.borders.get("top")) is Some((space, border)) {
        area.y += space + border.extent()
      }
      first_border = false
    }
    block.place(area, cache, probe, profile, images, additive)
  }
  guard area.pages.length() == 1 else {
    @failure.reject(
      "unsupported-layout", "Paragraph frames spanning pages are unsupported",
    )
  }
  let content = area.pages[0]
  if frame.width == 0 {
    if blocks is [BodyParagraph(p)] && content.lines is [line] {
      width = line.width + p.left + p.first + p.right
      if p.align != "left" {
        // Auto-width frames use the same paragraph at its intrinsic width.
        let measured = Pagination::new({ ..area.page, width, })
        measured.paragraph(cache, probe, p, profile, images, additive)
        content.lines.clear()
        content.lines.append(measured.pages[0].lines)
      }
    } else if blocks[0] is TableStart(table) {
      width = table.widths.fold(init=0.0, (sum, width) => sum + width) -
        (if table.legacyCellAlignment {
          table.cell_insets(0, 0).left +
          table.cell_insets(0, table.rows[0].length() - 1).right
        } else {
          0.0
        })
    }
  }
  let natural_height = area.y + area.after + area.gap
  let height = match frame.heightRule {
    "exact" => if frame.height > 0 { frame.height } else { natural_height }
    "atLeast" => frame.height.max(natural_height)
    "auto" => natural_height
    _ => @failure.reject("invalid-style", "Invalid paragraph frame height rule")
  }
  guard width > 0 && width <= 14400 && height > 0 && height <= self.page.height else {
    @failure.reject("layout-overflow", "Paragraph frame exceeds page bounds")
  }
  let x : Double = if frame.horizontalAlign.is_empty() &&
    frame.x is Some(offset) {
    (if frame.horizontalAnchor == "page" { 0.0 } else { self.anchorPage.left }) +
    offset
  } else {
    let (origin, extent) = if frame.horizontalAnchor == "page" {
      (0.0, self.page.width)
    } else {
      (self.page.left, available)
    }
    match frame.horizontalAlign {
      "center" => origin + (extent - width) / 2
      "right" =>
        if frame.horizontalAnchor == "page" {
          self.page.width - self.anchorPage.right
        } else {
          origin + extent - width
        }
      _ =>
        if frame.horizontalAnchor == "page" {
          self.anchorPage.left - width
        } else {
          origin
        }
    }
  }
  let x = x.max(0)
  let mut y = if frame.verticalAlign.is_empty() {
    let offset = frame.y.unwrap_or(0)
    match frame.verticalAnchor {
      "page" => offset
      "margin" =>
        if offset == 0 {
          self.y
        } else {
          self.anchorPage.top + offset
        }
      _ => self.y + offset
    }
  } else if frame.verticalAnchor == "text" {
    self.y
  } else {
    let (origin, extent) = if frame.verticalAnchor == "page" {
      (0.0, self.page.height)
    } else {
      (
        self.anchorPage.top,
        self.page.height - self.anchorPage.top - self.anchorPage.bottom,
      )
    }
    match frame.verticalAlign {
      "center" => origin + (extent - height) / 2
      "bottom" => origin + extent - height
      _ => origin
    }
  }
  y = (((y.min(self.page.height - height) * 20).round() + 1) / 20).max(0)
  guard content.lines.length() <= 32768 - self.count else {
    @failure.reject("limit-exceeded", "Paragraph frame line budget exceeded")
  }
  self.count += content.lines.length()
  let target = self.pages.last().unwrap()
  let (gap_left, gap_right) = if blocks[0] is TableStart(table) &&
    table.legacyCellAlignment {
    (
      table.cell_insets(0, 0).left,
      table.cell_insets(0, table.rows[0].length() - 1).right,
    )
  } else {
    (
      frame.borders
      .get("left")
      .map(e => e.0 + e.1.width + 72 / 25.4)
      .unwrap_or(0),
      frame.borders
      .get("right")
      .map(e => e.0 + e.1.width + 72 / 25.4)
      .unwrap_or(0),
    )
  }
  let clipped = content.clipped_to({
    x: -gap_left - 0.75,
    y: -0.75,
    width: width + gap_left + gap_right + 1.5,
    height: (height - 0.1).max(0) + 1.5,
  })
  target.lines.append(clipped.lines.map(line => line.shifted(x, y)))
  target.append_decoration(clipped, x, y)
  self.paint_frame_borders(frame, blocks, content, x, y, width)
  let id = content.lines.get(0).map(l => l.paragraph).unwrap_or(-1)
  let previous = self.wrapping.search_by(rect => {
    rect.paragraph == id && rect.start == -1
  })
  let rect : WrappingRect = {
    page: (self.pages.length() - 1) / self.columns.count,
    paragraph: id,
    start: -1,
    left: x - frame.horizontalSpace,
    right: x + width + frame.horizontalSpace,
    top: y - frame.verticalSpace,
    bottom: y + (height - 0.1).max(0) + frame.verticalSpace,
    wrapping: "topBottom",
    side: "bothSides",
  }
  if previous is Some(index) {
    self.wrapping[index] = rect
  } else {
    self.wrapping.push(rect)
  }
}

///|
fn Pagination::paint_frame_borders(
  self : Pagination,
  frame : ParagraphFrame,
  blocks : Array[BodyBlock],
  content : PageFrame,
  x : Double,
  y : Double,
  width : Double,
) -> Unit raise @failure.Failure {
  guard blocks[0] is BodyParagraph(_) else { return }
  let page = self.pages.last().unwrap()
  let left = frame.borders
    .get("left")
    .map(e => e.0 + e.1.width / 2 + 36 / 25.4)
    .unwrap_or(0)
  let right = frame.borders
    .get("right")
    .map(e => e.0 + e.1.width / 2 + 36 / 25.4)
    .unwrap_or(0)
  let bottom = content.lines.fold(init=0.0, (v, line) => {
    v.max(line.y + line.height)
  })
  for side in ["left", "right", "top", "bottom"] {
    if frame.borders.get(side) is Some((space, edge)) {
      let vertical = side == "left" || side == "right"
      let rect : Border = if vertical {
        {
          x: if side == "left" {
            x - left
          } else {
            x + width + right
          },
          y,
          width: 0,
          height: bottom + space,
        }
      } else {
        {
          x: x - left - edge.width / 2,
          y: if side == "top" {
            y + edge.width / 2
          } else {
            y + bottom + space + edge.width / 2
          },
          width: width + left + right + edge.width,
          height: 0,
        }
      }
      page.paint_table_border(rect, edge)
    }
  }
}
