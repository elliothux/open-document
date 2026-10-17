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
  mode : String,
  source : String,
  range : String,
  direction : String,
) -> Json raise @failure.Failure {
  guard ["linear", "growth"].contains(mode) else {
    @failure.reject("invalid-operation", "Invalid numeric series mode")
  }
  let growth = mode == "growth"
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
  let first = if vertical { source.top } else { source.left }
  let first_lane = if vertical { selected.left } else { selected.top }
  let last_lane = if vertical { selected.right } else { selected.bottom }
  let plans : Map[Int, SeriesTrend] = Map([])
  for lane in first_lane..<=last_lane {
    plans[lane] = current.series_trend(source, lane, vertical, growth)
  }
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  for row in selected.top..<=selected.bottom {
    for column in selected.left..<=selected.right {
      let address : Address = { row, column, }
      if source.contains(address) {
        continue
      }
      let plan = plans[if vertical { column } else { row }]
      let x = (if vertical { row - first } else { column - first }).to_double()
      let trend = plan.mean + plan.slope * (x - plan.origin)
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
      let key = address.name()
      let old = current.cells.get(key)
      if old.bind(cell => cell.formula) is Some(_) ||
        old.map(cell => cell.value).unwrap_or(Blank) != Number(value) ||
        current.style_at(address) != plan.style {
        updates[key] = {
          value: Number(value),
          formula: None,
          keep_shared: false,
        }
        styles[key] = plan.style
      }
    }
  }
  self.commit_fill(index, selected, updates, styles)
}
