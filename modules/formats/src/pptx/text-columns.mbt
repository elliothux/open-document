///|
fn text_column_width(
  body : Body,
  width : Double,
) -> Double raise @failure.Failure {
  let usable = width -
    body.left -
    body.right -
    (body.columns - 1).to_double() * body.columnGap
  guard usable > 0 else {
    @failure.reject(
      "layout-overflow", "Text column spacing leaves no usable width",
    )
  }
  usable / body.columns.to_double()
}

///|
fn place_text_columns(
  lines : Array[@layout.Line],
  object : Object,
  width : Double,
  height : Double,
  place : Bool,
) -> (Array[@layout.Line], Int, Double) {
  let body = object.body
  let output : Array[@layout.Line] = []
  let mut column = 0
  let mut bottom = 0.0
  let mut maximum = 0.0
  let mut previous = body.top
  for index, line in lines {
    let mut gap = line.y - previous
    if index > 0 && bottom + gap + line.height > height + 0.000001 {
      column += 1
      bottom = 0
      gap = if lines[index - 1].paragraph == line.paragraph {
        0
      } else {
        object.paragraphs[line.paragraph].before.points(line.height)
      }
    }
    if place {
      let at = if body.rtlColumns { body.columns - column - 1 } else { column }
      let dx = at.to_double() * (width + body.columnGap)
      let dy = body.top + bottom + gap - line.y
      output.push({
        ..line,
        x: line.x + dx,
        y: line.y + dy,
        areaX: line.areaX + dx,
        runs: line.runs.map(run => {
          ..run,
          x: run.x + dx,
          baseline: run.baseline + dy,
        }),
        marker: line.marker.map(run => {
          ..run,
          x: run.x + dx,
          baseline: run.baseline + dy,
        }),
        drawings: line.drawings.map(drawing => {
          ..drawing,
          x: drawing.x + dx,
          y: drawing.y + dy,
        }),
      })
    }
    bottom += gap + line.height
    maximum = maximum.max(bottom)
    previous = line.y + line.height
  }
  (output, column + 1, maximum)
}

///|
fn text_columns(
  lines : Array[@layout.Line],
  object : Object,
  geometry : Geometry,
  total : Double,
) -> (Array[@layout.Line], Double) raise @failure.Failure {
  let body = object.body
  if body.columns == 1 || lines.is_empty() {
    return (lines, total)
  }
  let width = text_column_width(body, geometry.width)
  let tail = total -
    body.bottom -
    lines.last().unwrap().y -
    lines.last().unwrap().height
  let mut height = (geometry.height - body.top - body.bottom).max(0)
  let fits = fn(height : Double) {
    let result = place_text_columns(lines, object, width, height, false)
    result.1 <= body.columns && result.2 + tail <= height + 0.000001
  }
  if !fits(height) {
    // ONLYOFFICE keeps the current column height unless content requires more space.
    let mut low = height
    let mut high = total - body.top - body.bottom
    for _ in 0..<32 {
      let trial = (low + high) / 2
      if fits(trial) {
        high = trial
      } else {
        low = trial
      }
    }
    height = high + 0.000001
  }
  let result = place_text_columns(lines, object, width, height, true)
  (result.0, result.2 + tail + body.top + body.bottom)
}
