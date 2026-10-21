///|
fn Object::table_cell(self : Object, cell : DrawingCell) -> Object {
  {
    ..self,
    table: None,
    source: cell.source,
    paragraphs: cell.paragraphs,
    body: cell.body,
    preset: "rect",
  }
}

///|
fn Object::paint_table(
  self : Object,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (
  Array[@layout.PositionedPrimitive],
  Array[@layout.Line],
  Array[String],
  Int,
) raise @failure.Failure {
  let table = self.table.unwrap()
  let output : Array[@layout.PositionedPrimitive] = []
  let lines : Array[@layout.Line] = []
  let diagnostics : Array[String] = []
  let fonts = probe.font_info()
  let mut y = 0.0
  let mut offset = 0
  let mut paragraph = 0
  let mut units = 0
  if !table.fill.is_empty() {
    output.push(
      Path(
        shape_path(
          "rect",
          self.geometry.unwrap().width,
          self.geometry.unwrap().height,
          (0, 0),
        ),
        table.fill,
        "",
        0,
        {
          fillAlpha: table.alpha,
          strokeAlpha: 1,
          dash: [],
          cap: 0,
          join: 0,
          miter: 8,
        },
      ),
    )
  }
  for r, row in table.rows {
    let mut x = 0.0
    for column, cell in row.cells {
      let advance = table.widths[column]
      if !cell.owner() {
        x += advance
        continue
      }
      let width = table.width(column, cell)
      let height = table.height(r, cell)
      let geometry = geometry_in_parent(
        0,
        0,
        width,
        height,
        0,
        false,
        false,
        @layout.Matrix::identity(),
      )
      if !cell.fill.is_empty() {
        output.push(Transform({ ..@layout.Matrix::identity(), e: x, f: y, }))
        output.push(
          Path(shape_path("rect", width, height, (0, 0)), cell.fill, "", 0, {
            fillAlpha: cell.alpha,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
        output.push(Restore)
      }
      let (measured, _, diagnostic) = fit_text(
        self.table_cell(cell),
        geometry,
        probe,
        profile,
      )
      if !diagnostic.is_empty() {
        diagnostics.push(self.id + ":" + diagnostic)
      }
      output.push(Clip({ x, y, width, height, }))
      for line in measured {
        let placed = {
          ..line,
          paragraph: line.paragraph + paragraph,
          start: line.start + offset,
          end: line.end + offset,
          x: line.x + x,
          y: line.y + y,
          areaX: line.areaX + x,
          cellClip: Some({ x, y, width, height, }),
          runs: line.runs.map(run => {
            ..run,
            x: run.x + x,
            baseline: run.baseline + y,
          }),
          marker: line.marker.map(run => {
            ..run,
            x: run.x + x,
            baseline: run.baseline + y,
          }),
          carets: line.carets.map(caret => {
            ..caret,
            offset: caret.offset + offset,
          }),
        }
        output.append(
          { ..placed, clip: false, }.positioned(
            fonts,
            self.geometry.unwrap().width,
          ),
        )
        units += [..line.marker, ..line.runs].fold(init=0, (sum, run) => {
          sum + run.glyphs.length()
        })
        guard units <= 262144 else {
          @failure.reject("limit-exceeded", "Table glyphs exceed budget")
        }
        lines.push(placed)
      }
      output.push(Restore)
      offset += cell.paragraphs.fold(init=0, (sum, p) => {
        sum + p.runs.fold(init=1, (sum, run) => sum + run.text.length())
      })
      paragraph += cell.paragraphs.length()
      x += advance
    }
    y += row.height
  }
  output.append(table.paint_edges())
  (output, lines, diagnostics, units)
}

///|
fn Object::table_fit_changes(
  self : Object,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let table = self.table.unwrap()
  let changes : Array[@xml.SourceChange] = []
  let heights = table.rows.map(row => row.height)
  for r, row in table.rows {
    for column, cell in row.cells {
      if !cell.owner() {
        continue
      }
      let height = heights[r:r + cell.row_span].fold(init=0.0, (sum, h) => {
        sum + h
      })
      let geometry = geometry_in_parent(
        0,
        0,
        table.width(column, cell),
        height,
        0,
        false,
        false,
        @layout.Matrix::identity(),
      )
      let target = self.table_cell(cell)
      let (_, measured) = measure_text(target, geometry, probe, profile, 1) catch {
        @failure.Failure(code="layout-overflow", ..) =>
          measure_text(
            { ..target, body: { ..target.body, wrap: false, }, },
            geometry,
            probe,
            profile,
            1,
          )
        error => raise error
      }
      let needed = (measured * 12700).ceil() / 12700
      if needed > height {
        heights[r + cell.row_span - 1] += needed - height
      }
    }
  }
  let mut total = 0.0
  for r, row in table.rows {
    let height = heights[r]
    total += height
    guard total <= 14400 else {
      @failure.reject("limit-exceeded", "Table height exceeds budget")
    }
    if height > row.height + 0.00001 {
      changes.push(
        attribute_change(
          row.source,
          "h",
          (height * 12700).round().to_int64().to_string(),
        ),
      )
    }
  }
  if !changes.is_empty() {
    let transform = self.source.child("xfrm", uri=presentation_uri).unwrap()
    changes.push(
      attribute_change(
        transform.child("ext").unwrap(),
        "cy",
        (total * 12700).round().to_int64().to_string(),
      ),
    )
  }
  changes
}
