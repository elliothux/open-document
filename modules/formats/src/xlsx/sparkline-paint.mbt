///|
fn Session::paint_sparkline(
  self : Session,
  index : Int,
  item : Sparkline,
  page : PagePaint,
  rect : @layout.Border,
  printing : Bool,
) -> Unit raise @failure.Failure {
  if rect.width <= 4 || rect.height <= 4 {
    return
  }
  guard item.source is Some(source) else { return }
  let sheet = self.sheets[index]
  let values : Array[Double?] = []
  for row in source.top..<=source.bottom {
    for column in source.left..<=source.right {
      if sheet.dimensions.rows.size(row) <= 0 ||
        sheet.dimensions.columns.size(column) <= 0 {
        continue
      }
      let address : Address = { row, column, }
      let cell = sheet.cells.get(address.name())
      let value = calculated_cell(
        self.sheets,
        self.calculation.unwrap().values,
        index,
        address,
      )
      if printing && cell.bind(c => c.formula) is Some(_) && value == Blank {
        @failure.reject("unsupported-print", "Uncalculated sparkline source")
      }
      values.push(
        match value {
          Number(n) => Some(n)
          _ => None
        },
      )
    }
  }
  let numbers = values.filter_map(n => n)
  if numbers.is_empty() {
    return
  }
  let scale = numbers.fold(init=0.0, (value, n) => value.max(n.abs())).max(1)
  let normalized = numbers.map(n => n / scale)
  let mut low = normalized.fold(init=normalized[0], (value, n) => value.min(n))
  let mut high = normalized.fold(init=normalized[0], (value, n) => value.max(n))
  if item.kind != "line" {
    low = low.min(0)
    high = high.max(0)
  }
  if item.kind == "winLoss" {
    low = -1
    high = 1
  }
  let left = rect.x + 2
  let top = rect.y + 2
  let width = rect.width - 4
  let height = rect.height - 4
  fn y(value : Double) -> Double {
    if low == high {
      top + height / 2
    } else {
      top + height * (1 - (value - low) / (high - low))
    }
  }
  let path : Array[@layout.PathSegment] = []
  let mut connected = false
  for i, value in values {
    if value is Some(value) {
      let n = value / scale
      if item.kind == "line" {
        let x = left +
          (if values.length() == 1 {
            width / 2
          } else {
            width * i.to_double() / (values.length() - 1).to_double()
          })
        path.push(if connected { Line(x, y(n)) } else { Move(x, y(n)) })
        // A single point or an isolated point must remain visible in a cell.
        if !connected && (i + 1 == values.length() || values[i + 1] is None) {
          page.bars.push(
            Rectangle({
              x: x - 0.75,
              y: y(n) - 0.75,
              width: 1.5,
              height: 1.5,
              color: "4472c4",
            }),
          )
        }
        connected = true
      } else if value != 0 {
        let slot = width / values.length().to_double()
        let end = y(
          if item.kind == "winLoss" {
            if value > 0 {
              1
            } else {
              -1
            }
          } else {
            n
          },
        )
        let zero = y(0)
        page.bars.push(
          Rectangle({
            x: left + i.to_double() * slot + slot * 0.15,
            y: end.min(zero),
            width: slot * 0.7,
            height: (end - zero).abs(),
            color: if value < 0 {
              "ed7d31"
            } else {
              "4472c4"
            },
          }),
        )
      }
    } else {
      connected = false
    }
  }
  if path.any(p => p is Line(_, _)) {
    page.bars.push(
      Path(path, "", "4472c4", 0.75, {
        fillAlpha: 1,
        strokeAlpha: 1,
        dash: [],
        cap: 0,
        join: 0,
        miter: 8,
      }),
    )
  }
}
