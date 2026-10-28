///|
fn measure_math_matrix(
  base : String,
  columns : ReadOnlyArray[String],
  rows : ReadOnlyArray[ReadOnlyArray[MathBox?]],
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
  paths : Ref[Int32],
) -> MathBox raise @failure.Failure {
  let placeholder = if rows
    .iter()
    .any(row => row.iter().any(cell => cell is None)) {
    Some(MathExpression::Text("⬚").measure(style, probe, profile, paths))
  } else {
    None
  }
  let boxes = rows.map(row => {
    row.map(cell => {
      match cell {
        Some(value) => value
        None => placeholder.unwrap()
      }
    })
  })
  let widths = columns.map(_ => 0.0).iter().collect()
  let ascents : Array[Double] = []
  let descents : Array[Double] = []
  for row in boxes {
    ascents.push(row.fold(init=0.0, (value, cell) => value.max(cell.ascent)))
    descents.push(
      row.fold(init=0.0, (value, cell) => value.max(cell.height - cell.ascent)),
    )
    for i, cell in row {
      widths[i] = widths[i].max(cell.width)
    }
  }
  // ONLYOFFICE matrix.js uses one-em columns and baseline-aware row intervals.
  let column_gap = style.size
  let minimum_gap = style.size * 11 / 36
  let interval = style.size * 7 / 6
  let primitives : Array[PositionedPrimitive] = []
  let mut height = 0.0
  for r, row in boxes {
    let mut x = 0.0
    for c, cell in row {
      let offset = match columns[c] {
        "left" => 0.0
        "right" => widths[c] - cell.width
        _ => (widths[c] - cell.width) / 2
      }
      cell.place(primitives, x + offset, height + ascents[r] - cell.ascent)
      x += widths[c] + column_gap
    }
    height += ascents[r] + descents[r]
    if r + 1 < boxes.length() {
      height += minimum_gap.max(interval - descents[r] - ascents[r + 1])
    }
  }
  let index = probe.math_font_index(style, profile)
  let ascent = if base == "top" || boxes.length() == 1 {
    ascents[0]
  } else if base == "bottom" {
    height - descents.last().unwrap()
  } else {
    height / 2 + 0.6 * probe.math_glyph_height(index, 0x2217, style.size)
  }
  {
    width: widths.fold(init=0.0, (sum, value) => sum + value) +
    (columns.length() - 1).to_double() * column_gap,
    height,
    ascent,
    primitives,
    textAscent: None,
  }
}
