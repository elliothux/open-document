///|
fn table_decoration(width : Double, height : Double) -> PageFrame {
  {
    width,
    height,
    lines: [],
    borders: [],
    fills: [],
    cellAreas: [],
    pageBorders: [],
  }
}

///|
fn PageFrame::append_decoration(
  self : PageFrame,
  source : PageFrame,
  x : Double,
  y : Double,
) -> Unit raise @failure.Failure {
  guard source.borders.length() <= 65536 - self.borders.length() &&
    source.cellAreas.length() <= 32768 - self.cellAreas.length() &&
    source.fills.length() <= 32768 - self.fills.length() else {
    @failure.reject(
      "limit-exceeded", "Nested table geometry exceeds page budget",
    )
  }
  self.borders.append(
    source.borders.map(stroke => {
      ..stroke,
      rect: { ..stroke.rect, x: stroke.rect.x + x, y: stroke.rect.y + y, },
    }),
  )
  self.fills.append(
    source.fills.map(fill => { ..fill, x: fill.x + x, y: fill.y + y, }),
  )
  self.cellAreas.append(
    source.cellAreas.map(area => {
      ..area,
      x: area.x + x,
      y: area.y + y,
      paragraphs: area.paragraphs.copy(),
    }),
  )
}

///|
/// Measure a contained native table in its cell coordinate system. Splitting a
/// nested row across physical pages requires a separate continuation contract.
fn Table::measure_nested(
  self : Table,
  cache : ParagraphCache,
  probe : TextProbe,
  page : PageSetup,
  profile : Map[String, String],
  additive : Bool,
) -> (Array[(Line, Double, Line)], Double, PageFrame) raise @failure.Failure {
  let table = self.fit_widths(probe, profile, page.width)
  table.check_grid()
  let decorations : Map[(Int32, Int32), PageFrame] = Map([])
  let (heights, cells) = table.measure_rows(
    cache,
    probe,
    page,
    0,
    table.rows.length() - 1,
    profile,
    additive,
    decorations~,
  )
  let height = heights.fold(init=0.0, (sum, height) => sum + height) +
    table.border_width(table.rows.length())
  guard height <= page.height - page.top - page.bottom else {
    @failure.reject(
      "unsupported-layout", "Nested tables spanning pages require continuation support",
    )
  }
  let frame = table_decoration(page.width, height)
  let result : Array[(Line, Double, Line)] = []
  let left = table.left(page)
  for (row, column, lines, content_height) in cells {
    let y = heights[:row].fold(init=0.0, (sum, height) => sum + height)
    let h = heights[row:row + table.rowSpans[row][column]].fold(init=0.0, (
      sum,
      height,
    ) => sum + height)
    let x = left +
      table.rows[row][:column]
      .mapi((c, _) => table.cell_width(row, c))
      .fold(init=0.0, (sum, width) => sum + width)
    let width = table.cell_width(row, column)
    frame.cellAreas.push({
      x,
      y,
      width,
      height: h,
      paragraphs: table.rows[row][column].map(p => p.id),
    })
    if !table.fills[row][column].is_empty() {
      frame.fills.push({
        x,
        y,
        width,
        height: h,
        color: table.fills[row][column],
      })
    }
    let extra = (h - content_height).max(0)
    let shift = match table.verticalAligns[row][column] {
      "center" => extra / 2
      "bottom" => extra
      _ => 0
    }
    let text_x = x + table.cell_insets(row, column).left
    let exact = table.exactHeights[row + table.rowSpans[row][column] - 1]
    if decorations.get((row, column)) is Some(child) {
      let child = if exact {
        child.clipped_to({ x: x - text_x, y: -shift, width, height: h, })
      } else {
        child
      }
      frame.append_decoration(child, text_x, y + shift)
    }
    for (line, offset, first) in lines {
      let translated_clip = line.cellClip.map(rect => {
        ..rect,
        x: rect.x + text_x,
        y: rect.y + y + shift,
      })
      let clip = if exact {
        let rect : Border = { x, y, width, height: h, }
        Some(
          translated_clip
          .map(inner => {
            inner.intersect(rect).unwrap_or({ ..rect, width: 0, height: 0, })
          })
          .unwrap_or(rect),
        )
      } else {
        translated_clip
      }
      let translated = {
        ..line,
        x: line.x + text_x,
        areaX: line.areaX + text_x,
        bars: line.bars.map(v => v + text_x),
        cellClip: clip,
      }
      result.push((translated, y + offset + shift, first))
    }
  }
  table.paint_borders(frame, 0, table.rows.length() - 1, left, 0, heights)
  (result, height, frame)
}
