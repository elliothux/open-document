///|
fn Sheet::automatic_series_values(
  self : Sheet,
  source : Range,
  lane : Int32,
  vertical : Bool,
  first : Int32,
  last : Int32,
  forward : Bool,
  styles : Array[CellStyle],
  date1904 : Bool,
  copy~ : Bool = false,
) -> Array[(Value, Int32, String?)] raise @failure.Failure {
  let values = if copy {
    Array::make(last - first + 1, (Blank, 0))
  } else {
    self.text_series_values(
      source,
      lane,
      vertical,
      first,
      last,
      forward,
      automatic=true,
      styles~,
      date1904~,
    )
  }
  let start = if vertical { source.top } else { source.left }
  let count = if vertical {
    source.bottom - source.top + 1
  } else {
    source.right - source.left + 1
  }
  let formulas : Map[String, Expression] = Map([])
  values.mapi((offset, item) => {
    let axis = first + offset
    let seed = start + ((axis - start) % count + count) % count
    let address : Address = if vertical {
      { row: seed, column: lane, }
    } else {
      { row: lane, column: seed, }
    }
    let cell = self.cells.get(address.name())
    let formula = cell
      .bind(cell => cell.formula)
      .map(text => {
        let expression = formulas
          .get(address.name())
          .unwrap_or_else(() => {
            let expression = parse_formula(text)
            formulas[address.name()] = expression
            expression
          })
        expression.source(
          rows=if vertical { axis - seed } else { 0 },
          columns=if vertical { 0 } else { axis - seed },
          invalid_ref=true,
        )
      })
    let value = if copy {
      cell.map(c => c.value).unwrap_or(Blank)
    } else {
      item.0
    }
    let style = if copy { self.style_at(address) } else { item.1 }
    (if formula is Some(_) { Blank } else { value }, style, formula)
  })
}
