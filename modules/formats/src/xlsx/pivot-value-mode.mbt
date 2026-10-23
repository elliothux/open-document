///|
// shortcut: Relative and ranking modes need base-item metadata when those modes are added.
let pivot_value_modes : ReadOnlyArray[String] = [
  "normal", "percentOfTotal", "percentOfRow", "percentOfCol", "index", "percentOfParentRow",
  "percentOfParentCol",
]

///|
fn pivot_percent(mode : String) -> Bool {
  [
    "percentOfTotal", "percentOfRow", "percentOfCol", "percentOfParentRow", "percentOfParentCol",
  ].contains(mode)
}

///|
fn pivot_ratio(value : Value, denominator : Value) -> Value {
  if value is Error(_) {
    return value
  }
  if denominator is Error(_) {
    return denominator
  }
  guard denominator is Number(divisor) else { return Blank }
  if divisor == 0 {
    return Error("#DIV/0!")
  }
  let numerator = if value is Number(number) { number } else { 0.0 }
  let result = numerator / divisor
  if result.is_nan() || result.is_inf() {
    Error("#NUM!")
  } else {
    Number(result)
  }
}

///|
fn PivotLayout::value_modes(self : PivotLayout) -> PivotLayout {
  let display = fn(
    value : Value,
    row : Value,
    column : Value,
    index : Int,
    row_members : Array[Int],
    column_members : Array[Int],
  ) {
    match self.settings.values[index].showDataAs {
      "normal" => value
      "percentOfTotal" =>
        if value == Blank {
          Number(0)
        } else {
          pivot_ratio(value, self.total[index])
        }
      "percentOfRow" => pivot_ratio(value, row)
      "percentOfCol" => pivot_ratio(value, column)
      "percentOfParentRow" | "percentOfParentCol" as mode => {
        let axis = if mode == "percentOfParentRow" {
          row_members
        } else {
          column_members
        }
        let denominator = if axis.is_empty() {
          value
        } else {
          let parent = axis[:axis.length() - 1].to_owned()
          let key = if mode == "percentOfParentRow" {
            Json((parent, column_members))
          } else {
            Json((row_members, parent))
          }
          self.parents
          .get(key.stringify())
          .map(values => values[index])
          .unwrap_or(Blank)
        }
        pivot_ratio(value, denominator)
      }
      "index" =>
        pivot_ratio(
          pivot_ratio(value, column),
          pivot_ratio(row, self.total[index]),
        )
      _ => abort("Validated pivot value mode")
    }
  }
  let count = self.settings.values.length()
  {
    ..self,
    values: self.values.mapi((row, values) => {
      values.mapi((at, value) => {
        let index = at % count
        display(
          value,
          self.row_totals[row][index],
          self.column_totals[at / count][index],
          index,
          self.members[row],
          self.columns[at / count],
        )
      })
    }),
    row_totals: self.row_totals.mapi((row, values) => {
      values.mapi((index, value) => {
        display(value, value, self.total[index], index, self.members[row], [])
      })
    }),
    column_totals: self.column_totals.mapi((column, values) => {
      values.mapi((index, value) => {
        display(
          value,
          self.total[index],
          value,
          index,
          [],
          self.columns[column],
        )
      })
    }),
    total: self.total.mapi((index, value) => {
      display(value, value, value, index, [], [])
    }),
  }
}

///|
fn Session::pivot_formats(
  self : Session,
  layout : PivotLayout,
  range : Range,
  sheet : Sheet,
  indices : Map[String, Int],
  previous~ : (Range, Int, Int, Array[PivotValue])? = None,
) -> StyleEdit? raise @failure.Failure {
  let originals : Map[String, (Int, Int)] = Map([])
  let body = layout.settings.body(range)
  let start = range.left + layout.settings.rows.length()
  for row in (body.top + layout.settings.header_rows())..<=range.bottom {
    for column in start..<=range.right {
      let address : Address = { row, column, }
      let key = address.name()
      let mode = layout.settings.values[(column - start) %
        layout.settings.values.length()].showDataAs
      let old = previous
        .map(info => {
          let (bounds, data_row, data_column, values) = info
          bounds.contains(address) &&
          row >= data_row &&
          column >= data_column &&
          values[(column - data_column) % values.length()].showDataAs !=
          "normal"
        })
        .unwrap_or(false)
      if mode == "normal" && !old {
        continue
      }
      let base = sheet.style_at(address)
      let format = if pivot_percent(mode) { "0.00%" } else { "General" }
      if self.styles[base].format != format {
        originals[key] = (base, if pivot_percent(mode) { 0 } else { 1 })
      }
    }
  }
  if originals.is_empty() {
    return None
  }
  let edit = self.derive_formats(originals, [
    CellFormat::new(numberFormat=Some("0.00%")),
    CellFormat::new(numberFormat=Some("General")),
  ])
  for key, index in edit.indices {
    indices[key] = index
  }
  Some(edit)
}
