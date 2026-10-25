///|
fn DrawingTable::table_opacity_changes(
  self : DrawingTable,
  row : Int,
  column : Int,
  sides : Array[Bool],
  value : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let cell = self.rows[row].cells[column]
  let changes : Array[@xml.SourceChange] = []
  let properties = cell.source.child("tcPr")
  let names = ["lnL", "lnR", "lnT", "lnB"]
  let added = StringBuilder()
  let amount = (value * 100000).round().to_int()
  for index, side in [0, 2, 1, 3] {
    if !sides[side] {
      continue
    }
    let segments = if side == 0 || side == 2 {
      [
        for r in row..<(row + cell.row_span) => {
          self.edge_paint(
            r,
            if side == 0 {
              column
            } else {
              column + cell.column_span
            },
            true,
          )
        }
      ]
    } else {
      [
        for c in column..<(column + cell.column_span) => {
          self.edge_paint(
            if side == 1 {
              row
            } else {
              row + cell.row_span
            },
            c,
            false,
          )
        }
      ]
    }
    if segments.all(segment => {
        segment.0.0.is_empty() ||
        (segment.0.3 * 100000).round().to_int() == amount
      }) {
      continue
    }
    let (border, source) = segments[0]
    guard segments.all(segment => {
      segment.0.0 == border.0 &&
      segment.0.1 == border.1 &&
      segment.0.2 == border.2
    }) else {
      @failure.reject(
        "protected-content", "Opacity editing cannot replace differing segments of a merged border",
      )
    }
    let name = names[index]
    guard source is Some((source, placeholder)) else {
      @failure.reject("protected-content", "Missing native table border color")
    }
    let markup = opacity_color_markup(source, placeholder, amount)
    if properties.bind(p => p.child(name)) is Some(edge) {
      let original = source_xml(edge)
      guard !original.contains("<!--") && !original.contains("<?") else {
        @failure.reject(
          "protected-content", "Retained table border markup is protected",
        )
      }
    }
    // A new direct pen must preserve the complete pre-edit shared winner.
    let xml = "<a:\{name} xmlns:a=\"\{drawing_uri}\" w=\"\{(border.1 * 12700).round().to_int64()}\">\{markup}<a:prstDash val=\"\{border.2}\"/></a:\{name}>"
    if properties is Some(properties) && !properties.node.empty {
      changes.push(
        paint_child_change(
          properties,
          properties.child(name).map(edge => edge.node),
          xml,
          [..names[index + 1:], "noFill", "solidFill"],
        ),
      )
    } else {
      added.write_string(xml)
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
