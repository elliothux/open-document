///|
fn Session::filter_rules(
  self : Session,
  index : Int,
  work : FormulaWork,
) -> ConditionalRules raise @failure.Failure {
  let rules = self.conditional_rules(
    self.sheets[index],
    index,
    self.sheets,
    work,
  )
  guard rules.reason.is_empty() else {
    @failure.reject("protected-content", rules.reason)
  }
  rules
}

///|
fn Session::filter_raw(
  self : Session,
  sheet : Int,
  row : Int,
  column : Int,
) -> Value raise @failure.Failure {
  let current = self.sheets[sheet]
  let address : Address = { row, column, }
  let name = address.name()
  let cell = current.cells.get(name)
  if cell.bind(c => c.formula) is Some(_) {
    self.calculation
    .bind(c => c.values.get((sheet, name)))
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-formula",
        part=current.id,
        offset=-1,
        message="Filtering requires current formula values",
      ),
    )
  } else {
    cell.map(c => c.value).unwrap_or(Blank)
  }
}

///|
fn Session::filter_value(
  self : Session,
  sheet : Int,
  row : Int,
  column : Int,
  rules : ConditionalRules,
  work : FormulaWork,
) -> String raise @failure.Failure {
  let current = self.sheets[sheet]
  let address : Address = { row, column, }
  let value = self.filter_raw(sheet, row, column)
  let style = rules.applied(
    self.styles[current.style_at(address)],
    address,
    self.sheets,
    sheet,
    self.calculation.map(c => c.values).unwrap_or(Map([])),
    work,
  )
  guard style.diagnostic.is_empty() else {
    @failure.reject("protected-content", style.diagnostic)
  }
  formatted(value, style.format, self.date1904).trim().to_owned()
}

///|
fn filter_normalized(
  text : String,
  work : FormulaWork,
) -> String raise @failure.Failure {
  work.spend(amount=text.length() + 1)
  guard formula_case(text.trim().to_owned(), false, work) is Text(value) else {
    @failure.reject("limit-exceeded", "Filter key exceeds normalization budget")
  }
  value
}

///|
fn Session::filtered_rows(
  self : Session,
  sheet : Int,
  settings : FilterSettings,
) -> Array[Int] raise @failure.Failure {
  let range = filter_settings(settings)
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: range.top, column: range.left, },
    names: self.formula_names(),
  }
  let rules = self.filter_rules(sheet, work)
  let normalized = settings.columns.map(column => {
    self.prepare_filter(sheet, range, column, work)
  })
  let hidden : Array[Int] = []
  for row in (range.top + 1)..<=range.bottom {
    for i, column in settings.columns {
      let value = self.filter_value(sheet, row, column.column, rules, work)
      if !normalized[i].matches(
          self.filter_raw(sheet, row, column.column),
          value,
          work,
        ) {
        hidden.push(row)
        break
      }
    }
  }
  hidden
}

///|
fn Session::filter_provenance(
  self : Session,
  index : Int,
  state : AutoFilterState,
) -> (Array[Int], Array[Int]) raise @failure.Failure {
  if state.tracked {
    return (state.manual, state.filtered)
  }
  // shortcut: Imported hidden/filter overlap is ambiguous without source provenance; tracked saves retain both masks.
  let fails = self.filtered_rows(index, state.settings)
  let manual : Array[Int] = []
  let filtered : Array[Int] = []
  for row in (state.bounds.top + 1)..<=state.bounds.bottom {
    if self.sheets[index].dimensions.rows.size(row) == 0 {
      if fails.contains(row) {
        filtered.push(row)
      } else {
        manual.push(row)
      }
    }
  }
  (manual, filtered)
}

///|
fn Session::filter_query(self : Session, index : Int) -> Json {
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  try {
    guard read_filter(current) is Some(state) else {
      return { "range": "", "columns": [], "catalog": [], "reason": reason }
    }
    let catalog : Array[Json] = []
    let mut units = 0
    let work : FormulaWork = {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: state.bounds.top, column: state.bounds.left, },
      names: self.formula_names(),
    }
    let rules = self.filter_rules(index, work)
    for column in state.bounds.left..<=state.bounds.right {
      let criterion = state.settings.columns
        .iter()
        .find_first(c => c.column == column)
      let selected : Map[String, Bool] = Map([])
      let values : Map[String, Int] = Map([])
      let labels : Map[String, String] = Map([])
      if criterion is Some({ rule: Values(allowed, ..), .. }) {
        for value in allowed {
          let key = filter_normalized(value, work)
          selected[key] = true
          labels[key] = value
          values[key] = 0
        }
      }
      let mut blanks = 0
      for row in (state.bounds.top + 1)..<=state.bounds.bottom {
        let value = self.filter_value(index, row, column, rules, work)
        units += value.length()
        guard units <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Filter catalog exceeds text budget",
          )
        }
        if value.is_empty() {
          blanks += 1
        } else {
          let key = filter_normalized(value, work)
          if !labels.contains(key) {
            labels[key] = value
          }
          values[key] = values.get(key).unwrap_or(0) + 1
        }
      }
      let ordered = values.keys().to_array()
      ordered.sort_by((a, b) => labels[a][:].lexical_compare(labels[b][:]))
      let title = self.filter_value(
        index,
        state.bounds.top,
        column,
        rules,
        work,
      )
      units += title.length()
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Filter catalog exceeds text budget")
      }
      catalog.push({
        "column": column,
        "title": title,
        "blank": blanks,
        "blankSelected": criterion
        .map(c => {
          match c.rule {
            Values(_, blank~) => blank
            Custom(_, ..) | Rank(_, ..) | Average(..) => true
          }
        })
        .unwrap_or(true),
        "values": ordered.map(value => {
          let item : Json = {
            "value": labels[value],
            "count": values[value],
            "selected": criterion is None ||
            !(criterion is Some({ rule: Values(_, ..), .. })) ||
            selected.contains(value),
          }
          item
        }),
      })
    }
    {
      "range": state.settings.range,
      "columns": state.settings.columns.map(c => c.json()),
      "catalog": catalog,
      "reason": reason,
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "range": "", "columns": [], "catalog": [], "reason": message }
  }
}
