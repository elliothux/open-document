///|
fn Sheet::automatic_series_values(
  self : Sheet,
  source : Range,
  lane : Int,
  vertical : Bool,
  first : Int,
  last : Int,
  forward : Bool,
  styles : Array[CellStyle],
  date1904 : Bool,
) -> Array[(Value, Int, String?)] raise @failure.Failure {
  let values = self.text_series_values(
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
    let formula = self.cells
      .get(address.name())
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
    (if formula is Some(_) { Blank } else { item.0 }, item.1, formula)
  })
}
