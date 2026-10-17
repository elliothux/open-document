///|
fn Session::selection_statistics(
  self : Session,
  sheet : Int,
  range : Range,
  cells : Array[Cell],
) -> Json raise @failure.Failure {
  let current = self.sheets[sheet]
  let mut count = 0
  let numbers : Array[Double] = []
  let mut uncomputed = ""
  for cell in cells {
    if current.dimensions.rows.size(cell.address.row) == 0 {
      continue
    }
    if cell.formula is Some(_) &&
      self.calculation.bind(c => c.values.get((sheet, cell.address.name())))
      is None {
      uncomputed = "Selection includes an uncalculated formula: " +
        cell.address.name()
    }
    let value = self.calculation
      .bind(calculation => calculation.values.get((sheet, cell.address.name())))
      .unwrap_or(cell.value)
    match value {
      Blank | Text("") => continue
      Number(value) => numbers.push(value)
      _ => ()
    }
    count += 1
  }
  let mut sum : Json = Json::null()
  let mut average : Json = Json::null()
  let mut minimum : Json = Json::null()
  let mut maximum : Json = Json::null()
  let mut reason = self.read_only
  if !numbers.is_empty() {
    let low = numbers.iter().fold(init=numbers[0], (a, b) => a.min(b))
    let high = numbers.iter().fold(init=numbers[0], (a, b) => a.max(b))
    minimum = Json(low)
    maximum = Json(high)
    let scale = low.abs().max(high.abs())
    // Scaling preserves finite averages even when the unscaled sum overflows.
    let mut total = 0.0
    let mut correction = 0.0
    for number in numbers {
      let value = if scale == 0 { 0.0 } else { number / scale }
      let next = total + value
      correction += if total.abs() >= value.abs() {
        total - next + value
      } else {
        value - next + total
      }
      total = next
    }
    let total = total + correction
    let value = total * scale
    if value.is_inf() || value.is_nan() {
      reason = if reason.is_empty() {
        "Selection sum exceeds the finite numeric range"
      } else {
        reason + "; Selection sum exceeds the finite numeric range"
      }
    } else {
      sum = Json(value)
    }
    average = Json(
      ((total / numbers.length().to_double()).clamp(min=-1, max=1) * scale).clamp(
        min=low,
        max=high,
      ),
    )
  }
  {
    "range": range.name(),
    "count": count,
    "countNumbers": numbers.length(),
    "sum": if uncomputed.is_empty() {
      sum
    } else {
      Json::null()
    },
    "average": if uncomputed.is_empty() {
      average
    } else {
      Json::null()
    },
    "min": if uncomputed.is_empty() {
      minimum
    } else {
      Json::null()
    },
    "max": if uncomputed.is_empty() {
      maximum
    } else {
      Json::null()
    },
    "reason": if uncomputed.is_empty() {
      reason
    } else {
      uncomputed
    },
  }
}
