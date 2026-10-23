///|
fn pivot_running_sum(previous : Value, value : Value) -> Value {
  if previous is Error(_) {
    return previous
  }
  if value is Error(_) {
    return value
  }
  let number = (if previous is Number(number) { number } else { 0.0 }) +
    (if value is Number(number) { number } else { 0.0 })
  if number.is_inf() || number.is_nan() {
    Error("#NUM!")
  } else {
    Number(number)
  }
}

///|
fn pivot_axis_series(
  mode : String,
  raw : Array[Value],
  parent : Value?,
) -> Array[Value] {
  if mode == "rankAscending" || mode == "rankDescending" {
    let numbers : Array[(Int, Double)] = []
    for position, value in raw {
      if value is Number(number) {
        numbers.push((position, number))
      }
    }
    numbers.sort_by((left, right) => {
      if mode == "rankAscending" {
        left.1.compare(right.1)
      } else {
        right.1.compare(left.1)
      }
    })
    let result = Array::make(raw.length(), Blank)
    let mut previous : Double? = None
    let mut rank = 0
    for (position, number) in numbers {
      if previous != Some(number) {
        rank += 1
      }
      result[position] = Number(rank.to_double())
      previous = Some(number)
    }
    return result
  }
  let mut sum = Number(0)
  let result = raw.map(value => {
    sum = pivot_running_sum(sum, value)
    sum
  })
  if mode != "percentOfRunningTotal" {
    return result
  }
  let denominator = parent.unwrap_or(result.last().unwrap_or(Number(0)))
  result.map(value => {
    if denominator == Blank || denominator == Number(0) {
      Blank
    } else {
      pivot_ratio(value, denominator)
    }
  })
}

///|
fn PivotLayout::base_values(self : PivotLayout) -> PivotLayout {
  if !self.settings.values.any(value => {
      pivot_base_mode(value.showDataAs) && value.showDataAs != "percentOfParent"
    }) {
    return self
  }
  let values = self.values.map(row => row.copy())
  let row_totals = self.row_totals.map(row => row.copy())
  let column_totals = self.column_totals.map(row => row.copy())
  let total = self.total.copy()
  let count = self.settings.values.length()
  for index, field in self.settings.values {
    if !pivot_base_mode(field.showDataAs) ||
      field.showDataAs == "percentOfParent" {
      continue
    }
    let base = field.baseField.unwrap()
    let fixed = match field.baseItem {
      Some(Member(item)) =>
        self.cache
        .axis_items(base)
        .search_by(value => pivot_item_key(value) == pivot_item_key(item))
      _ => None
    }
    let row_axis = self.settings.rows.contains(base)
    let fields = if row_axis {
      self.settings.rows
    } else {
      self.settings.columns
    }
    let at = fields.search_by(field => field == base).unwrap()
    let axis = if row_axis { self.members } else { self.columns }
    let lanes = if row_axis {
      self.columns.length()
    } else {
      self.members.length()
    }
    let groups : Map[String, Array[Int]] = Map([])
    for position, members in axis {
      if members.length() > at {
        // Hold every other member and subtotal depth fixed while advancing the base field.
        let key = Json(members[:at].to_owned() + members[at + 1:].to_owned()).stringify()
        groups.get_or_init(key, () => []).push(position)
      }
    }
    for lane in 0..<=lanes {
      let shown = Array::make(axis.length(), Blank)
      for positions in groups.values() {
        let raw = positions.map(position => {
          if lane == lanes {
            if row_axis {
              self.row_totals[position][index]
            } else {
              self.column_totals[position][index]
            }
          } else if row_axis {
            self.values[position][lane * count + index]
          } else {
            self.values[lane][position * count + index]
          }
        })
        let members = axis[positions[0]]
        let parent = if field.showDataAs == "percentOfRunningTotal" &&
          members.length() == at + 1 {
          let prefix = members[:at].to_owned()
          let other = if lane == lanes {
            []
          } else if row_axis {
            self.columns[lane]
          } else {
            self.members[lane]
          }
          let key = if row_axis {
            Json((prefix, other))
          } else {
            Json((other, prefix))
          }
          Some(
            self.parents
            .get(key.stringify())
            .map(values => values[index])
            .unwrap_or(Blank),
          )
        } else {
          None
        }
        let series = if pivot_compare_mode(field.showDataAs) {
          pivot_compare_series(
            field,
            raw,
            positions.map(position => axis[position][at]),
            fixed,
          )
        } else {
          pivot_axis_series(field.showDataAs, raw, parent)
        }
        for offset, position in positions {
          shown[position] = series[offset]
        }
      }
      for position, value in shown {
        if lane == lanes {
          if row_axis {
            row_totals[position][index] = value
          } else {
            column_totals[position][index] = value
          }
        } else if row_axis {
          values[position][lane * count + index] = value
        } else {
          values[lane][position * count + index] = value
        }
      }
    }
    for margin in (if row_axis { column_totals } else { row_totals }) {
      margin[index] = Blank
    }
    total[index] = Blank
  }
  { ..self, values, row_totals, column_totals, total, }
}
