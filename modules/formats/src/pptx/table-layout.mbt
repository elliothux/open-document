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
  for row in table.rows {
    let mut x = 0.0
    for column, cell in row.cells {
      let width = table.widths[column]
      let geometry = geometry_in_parent(
        0,
        0,
        width,
        row.height,
        0,
        false,
        false,
        @layout.Matrix::identity(),
      )
      if !cell.fill.is_empty() {
        output.push(Transform({ ..@layout.Matrix::identity(), e: x, f: y, }))
        output.push(
          Path(
            shape_path("rect", width, row.height, (0, 0)),
            cell.fill,
            "",
            0,
            {
              fillAlpha: cell.alpha,
              strokeAlpha: 1,
              dash: [],
              cap: 0,
              join: 0,
              miter: 8,
            },
          ),
        )
        output.push(Restore)
      }
      for side, (color, pen) in cell.borders {
        if color.is_empty() {
          continue
        }
        let (x1, y1, x2, y2) = match side {
          0 => (x, y, x, y + row.height)
          1 => (x, y, x + width, y)
          2 => (x + width, y, x + width, y + row.height)
          _ => (x, y + row.height, x + width, y + row.height)
        }
        output.push(
          Path([Move(x1, y1), Line(x2, y2)], "", color, pen, {
            fillAlpha: 1,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
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
      output.push(Clip({ x, y, width, height: row.height, }))
      for line in measured {
        let placed = {
          ..line,
          paragraph: line.paragraph + paragraph,
          start: line.start + offset,
          end: line.end + offset,
          x: line.x + x,
          y: line.y + y,
          areaX: line.areaX + x,
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
      x += width
    }
    y += row.height
  }
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
  let mut total = 0.0
  for row in table.rows {
    let mut height = row.height
    for column, cell in row.cells {
      let geometry = geometry_in_parent(
        0,
        0,
        table.widths[column],
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
      height = height.max(measured)
    }
    height = (height * 12700).ceil() / 12700
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
