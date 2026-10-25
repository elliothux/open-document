///|
fn DrawingTable::border_targets(
  self : DrawingTable,
  range : TableRange,
) -> Array[Array[Array[Bool]]] raise @failure.Failure {
  let targets = self.rows.map(row => {
    row.cells.map(_ => [false, false, false, false])
  })
  for r in range.top..<=range.bottom {
    for c in range.left..<=range.right {
      if self.rows[r].cells[c].owner() {
        targets[r][c] = [true, true, true, true]
      }
    }
  }
  for
    (side, edge, first, last) in [
      (3, range.top - 1, range.left, range.right),
      (1, range.bottom + 1, range.left, range.right),
      (if self.rtl { 0 } else { 2 }, range.left - 1, range.top, range.bottom),
      (if self.rtl { 2 } else { 0 }, range.right + 1, range.top, range.bottom),
    ] {
    let horizontal = side == 1 || side == 3
    if edge < 0 ||
      edge >=
      (if horizontal { self.rows.length() } else { self.widths.length() }) {
      continue
    }
    for at in first..<=last {
      let (r, c) = if horizontal {
        self.owners[edge][at]
      } else {
        self.owners[at][edge]
      }
      let cell = self.rows[r].cells[c]
      let start = if horizontal { c } else { r }
      let end = start +
        (if horizontal { cell.column_span } else { cell.row_span }) -
        1
      guard start >= first && end <= last else {
        @failure.reject(
          "protected-content", "A shared border covers only part of an adjacent merged cell",
        )
      }
      targets[r][c][side] = true
    }
  }
  targets
}

///|
fn table_border_changes(
  cell : DrawingCell,
  sides : Array[Bool],
  color : String?,
  width : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let added = StringBuilder()
  let properties = cell.source.child("tcPr")
  let names = ["lnL", "lnR", "lnT", "lnB"]
  for index, side in [0, 2, 1, 3] {
    if !sides[side] {
      continue
    }
    let name = names[index]
    let edge = properties.bind(p => p.child(name))
    if edge is Some(edge) &&
      same_paint(edge, color, opacity=cell.borders[side].3) &&
      (color is None || cell.borders[side].1 == width) {
      continue
    }
    if edge is Some(edge) {
      let source = source_xml(edge)
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Unknown table border source is protected",
        )
      }
      ignore(paint_fill(edge))
    }
    let dash = cell.borders[side].2
    let xml = "<a:\{name} xmlns:a=\"\{drawing_uri}\" w=\"\{(width * 12700).round().to_int64()}\">\{paint_markup(color, opacity=cell.borders[side].3)}<a:prstDash val=\"\{dash}\"/></a:\{name}>"
    if properties is Some(properties) && !properties.node.empty {
      changes.push(
        paint_child_change(
          properties,
          edge.map(e => e.node),
          xml,
          [..names[index + 1:], "noFill", "solidFill"],
        ),
      )
    } else {
      added.write_string(xml)
    }
  }
  if !added.to_string().is_empty() {
    changes.push(
      if properties is Some(properties) {
        insertion(properties.node, added.to_string())
      } else {
        insertion(
          cell.source.node,
          "<a:tcPr xmlns:a=\"\{drawing_uri}\">\{added}</a:tcPr>",
        )
      },
    )
  }
  changes
}

///|
fn table_dash_changes(
  cell : DrawingCell,
  sides : Array[Bool],
  value : String?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let properties = cell.source.child("tcPr")
  let names = ["lnL", "lnR", "lnT", "lnB"]
  let added = StringBuilder()
  for index, side in [0, 2, 1, 3] {
    if !sides[side] {
      continue
    }
    let name = names[index]
    let markup = value
      .map(value => "<a:prstDash xmlns:a=\"\{drawing_uri}\" val=\"\{value}\"/>")
      .unwrap_or("")
    if properties.bind(p => p.child(name)) is Some(edge) {
      let preset = dash_override(edge)
      if value == preset.map(p => p.node.attribute("val").unwrap_or("solid")) {
        continue
      }
      if preset is Some(preset) {
        let source = source_xml(preset)
        guard !source.contains("<!--") && !source.contains("<?") else {
          @failure.reject(
            "protected-content", "Retained table border dash is protected",
          )
        }
      }
      changes.push(
        paint_child_change(edge, preset.map(p => p.node), markup, []),
      )
    } else if value is Some(_) {
      let xml = "<a:\{name} xmlns:a=\"\{drawing_uri}\">\{markup}</a:\{name}>"
      if properties is Some(properties) && !properties.node.empty {
        changes.push(
          paint_child_change(
            properties,
            None,
            xml,
            [..names[index + 1:], "noFill", "solidFill"],
          ),
        )
      } else {
        added.write_string(xml)
      }
    }
  }
  if !added.is_empty() {
    changes.push(
      if properties is Some(properties) {
        insertion(properties.node, added.to_string())
      } else {
        insertion(
          cell.source.node,
          "<a:tcPr xmlns:a=\"\{drawing_uri}\">\{added}</a:tcPr>",
        )
      },
    )
  }
  changes
}
