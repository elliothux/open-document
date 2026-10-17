///|
pub(all) enum SeriesMode {
  Linear
  Growth
  Date(String, Double)
}

///|
priv struct SeriesTrend {
  origin : Double
  mean : Double
  slope : Double
  scale : Double
  style : Int
}

///|
fn Sheet::series_trend(
  self : Sheet,
  source : Range,
  lane : Int,
  vertical : Bool,
  growth : Bool,
) -> SeriesTrend raise @failure.Failure {
  let first = if vertical { source.top } else { source.left }
  let last = if vertical { source.bottom } else { source.right }
  let points : Array[(Double, Double)] = []
  let mut style = 0
  let mut scale = 1.0
  let mut first_value = 0.0
  let mut first_log = 0.0
  for index in first..<=last {
    let address : Address = if vertical {
      { row: index, column: lane, }
    } else {
      { row: lane, column: index, }
    }
    let cell = self.cells.get(address.name())
    guard cell.bind(cell => cell.formula) is None else {
      @failure.reject(
        "invalid-operation", "Numeric series requires literal numeric seeds",
      )
    }
    match cell.map(cell => cell.value).unwrap_or(Blank) {
      Number(value) => {
        guard !value.is_nan() && !value.is_inf() else {
          @failure.reject(
            "invalid-operation", "Numeric series seeds must be finite",
          )
        }
        guard !growth || value > 0 else {
          @failure.reject(
            "invalid-operation", "Growth series requires positive numeric seeds",
          )
        }
        if points.is_empty() {
          style = self.style_at(address)
          first_value = value
          if growth {
            first_log = @math.ln(value)
          }
        }
        points.push(
          (
            (index - first).to_double(),
            if growth {
              @math.ln(value) - first_log
            } else {
              value
            },
          ),
        )
        if !growth {
          scale = scale.max(value.abs())
        }
      }
      Blank => ()
      _ =>
        @failure.reject(
          "invalid-operation", "Numeric series requires numeric seeds or blanks",
        )
    }
  }
  guard !points.is_empty() else {
    @failure.reject(
      "invalid-operation", "Every series lane needs a numeric seed",
    )
  }
  if points.length() == 1 {
    return {
      origin: points[0].0,
      mean: if growth {
        0
      } else {
        points[0].1
      },
      slope: if growth {
        0
      } else {
        1
      },
      scale: if growth {
        first_value
      } else {
        1
      },
      style,
    }
  }
  let count = points.length().to_double()
  // Scale extreme seeds before summation so finite trends do not overflow intermediate sums.
  let scale = if scale > 1.0e150 { scale } else { 1.0 }
  let origin = points.fold(init=0.0, (sum, p) => sum + p.0) / count
  let mean = points.fold(init=0.0, (sum, p) => sum + p.1 / scale) / count
  let numerator = points.fold(init=0.0, (sum, p) => {
    sum + (p.0 - origin) * (p.1 / scale - mean)
  })
  let denominator = points.fold(init=0.0, (sum, p) => {
    sum + (p.0 - origin) * (p.0 - origin)
  })
  {
    origin,
    mean,
    slope: numerator / denominator,
    scale: if growth {
      first_value
    } else {
      scale
    },
    style,
  }
}

///|
fn Session::fill_series(
  self : Session,
  sheet : String,
  mode : SeriesMode,
  source : String,
  range : String,
  direction : String,
) -> Json raise @failure.Failure {
  if mode is Date(unit, step) {
    guard ["day", "weekday", "month", "year"].contains(unit) &&
      !step.is_nan() &&
      !step.is_inf() &&
      step.abs() <= 2958465 &&
      (unit == "day" || step == step.trunc()) else {
      @failure.reject("invalid-operation", "Invalid date series unit or step")
    }
  }
  let growth = mode is Growth
  guard ["down", "up", "right", "left"].contains(direction) else {
    @failure.reject("invalid-operation", "Invalid numeric series direction")
  }
  let source = Range::parse(source)
  let selected = Range::parse(range)
  guard (selected.bottom - selected.top + 1).to_int64() *
    (selected.right - selected.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Numeric series exceeds 4096 cells")
  }
  let vertical = direction == "down" || direction == "up"
  let forward = direction == "down" || direction == "right"
  if mode is Date(_, _) {
    guard (if vertical {
      source.top == source.bottom
    } else {
      source.left == source.right
    }) else {
      @failure.reject(
        "invalid-operation", "Date series needs one seed per lane",
      )
    }
  }
  guard selected.contains({ row: source.top, column: source.left, }) &&
    selected.contains({ row: source.bottom, column: source.right, }) &&
    (if vertical {
      source.left == selected.left && source.right == selected.right
    } else {
      source.top == selected.top && source.bottom == selected.bottom
    }) &&
    (if vertical {
      if forward {
        source.top == selected.top
      } else {
        source.bottom == selected.bottom
      }
    } else if forward {
      source.left == selected.left
    } else {
      source.right == selected.right
    }) else {
    @failure.reject(
      "invalid-operation", "Series source must span the selected leading edge",
    )
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  if source == selected {
    return self.query()
  }
  self.check_fill_cells(current, [selected])
  self.check_fill_resources(current, selected)
  if read_filter(current) is Some(filter) &&
    !filter.settings.columns.is_empty() &&
    filter.bounds.intersects(selected) {
    @failure.reject(
      "protected-content", "Filtered ranges require visible-cell series support",
    )
  }
  let first = if vertical { selected.top } else { selected.left }
  let last = if vertical { selected.bottom } else { selected.right }
  let first_lane = if vertical { selected.left } else { selected.top }
  let last_lane = if vertical { selected.right } else { selected.bottom }
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  for lane in first_lane..<=last_lane {
    let (values, style) = match mode {
      Date(unit, step) => {
        let seed : Address = if vertical {
          { row: source.top, column: lane, }
        } else {
          { row: lane, column: source.left, }
        }
        guard current.cells.get(seed.name()) is Some(cell) &&
          cell.formula is None &&
          cell.value is Number(value) else {
          @failure.reject(
            "invalid-operation", "Date series needs literal numeric seeds",
          )
        }
        let values = date_series_values(
          value,
          unit,
          if forward {
            step
          } else {
            -step
          },
          last - first + 1,
          self.date1904,
        )
        (if forward { values } else { values.rev() }, current.style_at(seed))
      }
      _ => {
        let plan = current.series_trend(source, lane, vertical, growth)
        let origin = if vertical { source.top } else { source.left }
        let values : Array[Double] = []
        for axis in first..<=last {
          let trend = plan.mean +
            plan.slope * ((axis - origin).to_double() - plan.origin)
          let value = if growth {
            if trend == 0 {
              plan.scale
            } else {
              @math.exp(@math.ln(plan.scale) + trend)
            }
          } else {
            trend * plan.scale
          }
          guard !value.is_nan() && !value.is_inf() else {
            @failure.reject(
              "invalid-operation", "Numeric series exceeds finite numeric range",
            )
          }
          values.push(value)
        }
        (values, plan.style)
      }
    }
    for offset, value in values {
      let address : Address = if vertical {
        { row: first + offset, column: lane, }
      } else {
        { row: lane, column: first + offset, }
      }
      if source.contains(address) {
        continue
      }
      let key = address.name()
      let old = current.cells.get(key)
      if old.bind(cell => cell.formula) is Some(_) ||
        old.map(cell => cell.value).unwrap_or(Blank) != Number(value) ||
        current.style_at(address) != style {
        updates[key] = {
          value: Number(value),
          formula: None,
          keep_shared: false,
        }
        styles[key] = style
      }
    }
  }
  self.commit_fill(index, selected, updates, styles)
}
