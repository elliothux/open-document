///|
fn measure_math_equation_array(
  base : String,
  rows : ReadOnlyArray[ReadOnlyArray[MathExpression?]],
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
  paths : Ref[Int32],
  display~ : Bool,
) -> MathBox raise @failure.Failure {
  let empty = MathExpression::Text(" ").measure(style, probe, profile, paths)
  let placeholder = if rows
    .iter()
    .any(row => row.iter().all(value => value is None)) {
    Some(MathExpression::Text("⬚").measure(style, probe, profile, paths))
  } else {
    None
  }
  let boxes = rows.map(row => {
    let blank = row.iter().all(value => value is None)
    row.mapi((index, value) => {
      value
      .map(value => value.measure(style, probe, profile, paths, display~))
      .unwrap_or(
        if blank && index == 0 {
          placeholder.unwrap()
        } else {
          { ..empty, width: 0, primitives: [], }
        },
      )
    })
  })
  let count = rows.fold(init=0, (value, row) => {
    value.max((row.length() + 1) / 2)
  })
  let left = Array::make(count, 0.0)
  let right = Array::make(count, 0.0)
  let widths = Array::make(count, 0.0)
  let largest = Array::make(count, 0.0)
  let centered = Array::make(count, 0.0)
  for row in boxes {
    for c, cell in row {
      let group = c / 2
      if c % 2 == 1 {
        right[group] = right[group].max(cell.width)
        left[group] = left[group].max(row[c - 1].width)
        if largest[group] < cell.width || largest[group] < row[c - 1].width {
          largest[group] = cell.width.max(row[c - 1].width)
          centered[group] = cell.width + row[c - 1].width
        }
      } else if c + 1 == row.length() {
        widths[group] = widths[group].max(cell.width)
        if largest[group] < cell.width {
          largest[group] = cell.width
          centered[group] = cell.width
        }
      }
    }
  }
  for i in 0..<count {
    widths[i] = widths[i].max(left[i] + right[i])
  }
  let ascents = boxes.map(row => {
    row.fold(init=0.0, (value, cell) => value.max(cell.ascent))
  })
  let descents = boxes.map(row => {
    row.fold(init=0.0, (value, cell) => value.max(cell.height - cell.ascent))
  })
  let primitives : Array[PositionedPrimitive] = []
  let mut height = 0.0
  // ONLYOFFICE CEqArray pairs alignment segments without matrix column gaps.
  for r, row in boxes {
    let mut x = 0.0
    for c, cell in row {
      let group = c / 2
      let offset = if c % 2 == 1 {
        (widths[group] - left[group] - right[group]) / 2 + left[group]
      } else if c + 1 < row.length() {
        (widths[group] - left[group] - right[group]) / 2 +
        left[group] -
        cell.width
      } else {
        (centered[group] - cell.width) / 2
      }
      cell.place(primitives, x + offset, height + ascents[r] - cell.ascent)
      if c % 2 == 1 {
        x += widths[group]
      }
    }
    height += ascents[r] + descents[r]
    if r + 1 < boxes.length() {
      height += (style.size * 11 / 36).max(
        style.size * 7 / 6 - descents[r] - ascents[r + 1],
      )
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
    width: widths.fold(init=0.0, (sum, value) => sum + value),
    height,
    ascent,
    primitives,
    textAscent: None,
  }
}
