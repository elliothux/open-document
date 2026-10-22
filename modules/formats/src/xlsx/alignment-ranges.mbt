///|
fn ConditionalRules::alignment_ranges(
  self : ConditionalRules,
  current : Sheet,
  styles : Array[CellStyle],
  rows : Map[Int, Bool],
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> Array[Range] raise @failure.Failure {
  if !styles.any(style => {
      ["centerContinuous", "fill"].contains(style.horizontal)
    }) &&
    !self.rules.any(rule => {
      rule.style.horizontal is Some("centerContinuous" | "fill")
    }) &&
    self.table_styles.custom.is_empty() {
    return []
  }
  work.spend(amount=current.cells.length())
  let cells = current.cells
    .values()
    .filter(cell => rows.contains(cell.address.row))
    .to_array()
  cells.sort_by((a, b) => {
    let row = a.address.row.compare(b.address.row)
    if row == 0 {
      a.address.column.compare(b.address.column)
    } else {
      row
    }
  })
  let result : Array[Range] = []
  let mut active : (Int, String, Range)? = None
  let finish = fn(run : (Int, String, Range)?) {
    if run is Some((_, _, range)) && range.left < range.right {
      result.push(range)
    }
  }
  for cell in cells {
    let style = self.applied(
      styles[cell.style],
      cell.address,
      sheets,
      index,
      values,
      work,
    )
    let eligible = if ["centerContinuous", "fill"].contains(style.horizontal) &&
      !(style.horizontal == "fill" && style.wrap) &&
      style.diagnostic.is_empty() {
      work.spend(amount=current.merges.length())
      !current.merges.any(range => range.contains(cell.address))
    } else {
      false
    }
    let empty = cell.formula is None &&
      (cell.value == Blank || cell.value == Text(""))
    if eligible &&
      empty &&
      active is Some((style_id, alignment, range)) &&
      style_id == cell.style &&
      alignment == style.horizontal &&
      range.top == cell.address.row &&
      range.right + 1 == cell.address.column {
      active = Some(
        (style_id, alignment, { ..range, right: cell.address.column, }),
      )
    } else {
      finish(active)
      active = if eligible && !empty {
        Some(
          (
            cell.style,
            style.horizontal,
            {
              top: cell.address.row,
              bottom: cell.address.row,
              left: cell.address.column,
              right: cell.address.column,
            },
          ),
        )
      } else {
        None
      }
    }
  }
  finish(active)
  result
}
