///|
priv struct SeriesCalendar {
  kind : String
  date1904 : Bool
  unit : String
  step : Int
  day : Int
  time_step : Double
  mut time_offset : Double
  mut previous : Double
}

///|
fn series_calendar_kind(format : String) -> String {
  match format {
    "yyyy-mm-dd" | "mm-dd-yy" | "d-mmm-yy" | "d-mmm" | "mmm-yy" => "date"
    "h:mm AM/PM" | "h:mm:ss AM/PM" | "h:mm" | "hh:mm:ss" => "time"
    "m/d/yy h:mm" => "datetime"
    _ => ""
  }
}

///|
fn series_calendar_plan(
  indices : Array[Int],
  suffixes : Array[(String?, Double, Int)?],
  kinds : Array[String],
  points : Array[(Double, Double)],
  forward : Bool,
  date1904 : Bool,
) -> (SeriesTrend, SeriesCalendar)? raise @failure.Failure {
  let limit = if date1904 { 2957004.0 } else { 2958466.0 }
  for index in indices {
    let value = suffixes[index].unwrap().1
    guard !value.is_nan() && !value.is_inf() && value >= 0 && value < limit else {
      @failure.reject(
        "invalid-operation", "Automatic date seed is outside the workbook calendar",
      )
    }
  }
  let date = indices.all(i => kinds[i] == "date")
  let time = indices.all(i => kinds[i] == "time")
  let mixed = !date && !time && indices.any(i => kinds[i] == "date")
  let fraction = indices
    .iter()
    .find_first(i => kinds[i] == "datetime")
    .map(i => {
      let value = suffixes[i].unwrap().1
      value - value.floor()
    })
    .unwrap_or(0)
  let values = points.map(point => {
    (
      point.0,
      if date || mixed {
        point.1.floor() + (if mixed { fraction } else { 0 })
      } else {
        point.1
      },
    )
  })
  let fitted = series_fit(values, false, values[0].1, 1, 0)
  let fitted = if indices.length() == 1 {
    {
      ..fitted,
      slope: (if forward { 1.0 } else { -1.0 }) /
      (if time { 24.0 } else { 1.0 }),
    }
  } else {
    fitted
  }
  let fitted = if time &&
    values[0].1.floor() != values[values.length() - 1].1.floor() {
    { ..fitted, slope: fitted.slope - fitted.slope.trunc(), }
  } else {
    fitted
  }
  let intercept = fitted.mean - fitted.slope * fitted.origin
  let mut unit = ""
  let mut step = 0
  if !time && indices.length() > 1 {
    let dates = indices.map(i => {
      date_parts(suffixes[i].unwrap().1.floor().to_int(), date1904)
    })
    let first = dates[0]
    let second = dates[1]
    if dates.all(d => d.2 == first.2) {
      if first.1 != second.1 {
        unit = "month"
      } else if first.0 != second.0 {
        unit = "year"
      }
      let units = dates.map(d => {
        if unit == "year" {
          d.0
        } else {
          d.0 * 12 + d.1 - 1
        }
      })
      let distance = points[1].0 - points[0].0
      let difference = (units[1] - units[0]).to_double() / distance
      step = difference.to_int()
      if !dates.all(d => unit != "year" || d.1 == first.1) ||
        difference != difference.trunc() ||
        !units
        .mapi((i, value) => {
          (value - units[0]).to_double() == difference * points[i].0
        })
        .all(value => value) {
        unit = ""
      }
    }
  }
  if unit.is_empty() &&
    date &&
    (
      fitted.slope == 0 ||
      fitted.slope != fitted.slope.trunc() ||
      intercept != intercept.trunc()
    ) {
    return None
  }
  if unit.is_empty() &&
    !date &&
    !time &&
    !mixed &&
    values.length() > 1 &&
    values[0].1.floor() != values[1].1.floor() &&
    (intercept - values[0].1).abs() > 0.0005 {
    return None
  }
  let seed = suffixes[indices[indices.length() - 1]].unwrap().1
  let fitted = if unit.is_empty() &&
    !date &&
    !time &&
    !mixed &&
    values.length() > 1 &&
    values[0].1.floor() == values[1].1.floor() &&
    (intercept - values[0].1).abs() > 0.0005 &&
    fitted.slope.abs() < 1 {
    { ..fitted, mean: values[0].1, origin: 0, slope: fitted.slope.trunc(), }
  } else {
    fitted
  }
  let times = points.map(point => (point.0, point.1 - point.1.floor()))
  let time_step = if !date && !mixed && !time && indices.length() > 1 {
    series_fit(times, false, times[0].1, 1, 0).slope
  } else {
    0
  }
  Some(
    (
      fitted,
      {
        kind: if time {
          "time"
        } else {
          "date"
        },
        date1904,
        unit,
        step,
        day: date_parts(seed.floor().to_int(), date1904).2,
        time_step,
        time_offset: 0,
        previous: if date {
          seed.floor()
        } else if mixed {
          seed.floor() + fraction
        } else {
          seed
        },
      },
    ),
  )
}

///|
fn SeriesCalendar::next(
  self : SeriesCalendar,
  fitted : Double,
) -> Double raise @failure.Failure {
  let calendar = if self.unit.is_empty() {
    fitted
  } else {
    date_series_values(
      self.previous,
      self.unit,
      self.step.to_double(),
      2,
      self.date1904,
      expectedDay=self.day,
    )[1]
  }
  self.previous = calendar
  if !self.unit.is_empty() {
    self.time_offset += self.time_step
  }
  let value = calendar + self.time_offset
  let value = if self.kind == "time" && value < 0 {
    value - value.floor()
  } else {
    value
  }
  guard !value.is_nan() &&
    !value.is_inf() &&
    value >= 0 &&
    value < (if self.date1904 { 2957004 } else { 2958466 }) else {
    @failure.reject(
      "invalid-operation", "Automatic date series exceeds the workbook calendar",
    )
  }
  value
}
