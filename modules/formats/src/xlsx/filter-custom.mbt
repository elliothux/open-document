///|
fn filter_operator(operator : String) -> String raise @failure.Failure {
  match operator {
    "equal" => "="
    "notEqual" => "<>"
    "greaterThan" => ">"
    "greaterThanOrEqual" => ">="
    "lessThan" => "<"
    "lessThanOrEqual" => "<="
    _ => @failure.reject("invalid-operation", "Unknown custom filter operator")
  }
}

///|
priv enum PreparedFilter {
  Labels(Map[String, Bool], blank~ : Bool)
  Conditions(Array[Criterion], all~ : Bool)
  Ranking(Double?, top~ : Bool)
  Mean(Double?, above~ : Bool)
  DateLabels(Array[(Double, Double)], Map[String, Bool], blank~ : Bool)
  CalendarMonths(Int, Int)
  DateInterval(Double, Double)
  Color(String, cell_color~ : Bool)
}

///|
fn FilterRule::prepare(
  self : FilterRule,
  work : FormulaWork,
) -> PreparedFilter raise @failure.Failure {
  match self {
    Relative(_, _) =>
      @failure.reject(
        "invalid-operation", "Relative dates require a session calendar context",
      )
    Calendar(unit, value) => {
      ignore(filter_calendar_type(unit, value))
      if unit == "month" {
        CalendarMonths(value, value)
      } else {
        CalendarMonths((value - 1) * 3 + 1, value * 3)
      }
    }
    Dates(groups, values~, blank~) =>
      prepare_date_filter(groups, values, blank, work)
    Rank(_, ..) | Average(..) | Color(_, ..) | ColorStyle(_, ..) =>
      @failure.reject(
        "invalid-operation", "Numeric filtering requires its source range",
      )
    Values(labels, blank~) => {
      let values : Map[String, Bool] = Map([])
      for value in labels {
        values[filter_normalized(value, work)] = true
      }
      Labels(values, blank~)
    }
    Custom(conditions, all~) => {
      let criteria = conditions.map(condition => {
        let operator = filter_operator(condition.operator)
        let text = filter_normalized(condition.value, work)
        let value = if text.is_empty() {
          Text("")
        } else {
          numeric_value(Text(text))
        }
        let value = if value is Number(_) { value } else { Text(text) }
        let pattern = if value is Text(_) &&
          ["=", "<>"].contains(operator) &&
          (text.contains("*") || text.contains("?") || text.contains("~")) {
          Some(formula_pattern(text, work))
        } else {
          None
        }
        { operator, value, pattern, }
      })
      Conditions(criteria, all~)
    }
  }
}

///|
fn PreparedFilter::matches(
  self : PreparedFilter,
  raw : Value,
  label : String,
  date : Bool,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  match self {
    DateInterval(start, end) =>
      match raw {
        Number(value) =>
          value >= 0 &&
          value < (if work.date1904 { 2957004 } else { 2958466 }) &&
          value >= start &&
          value < end
        _ => false
      }
    CalendarMonths(first, last) =>
      match raw {
        Number(value) => filter_calendar_matches(first, last, value, work)
        _ => false
      }
    Color(_, ..) =>
      @failure.reject(
        "invalid-operation", "Color filtering requires an effective style",
      )
    DateLabels(intervals, values, blank~) =>
      if label.is_empty() {
        blank
      } else if date {
        match raw {
          Number(value) => filter_date_matches(intervals, value, work)
          _ => false
        }
      } else {
        values.contains(filter_normalized(label, work))
      }
    Mean(threshold, above~) =>
      match (raw, threshold) {
        (Number(value), Some(limit)) =>
          if above {
            value > limit
          } else {
            value < limit
          }
        _ => false
      }
    Ranking(threshold, top~) =>
      match (raw, threshold) {
        (Number(value), Some(limit)) =>
          if top {
            value >= limit
          } else {
            value <= limit
          }
        _ => false
      }
    Labels(values, blank~) =>
      if label.is_empty() {
        blank
      } else {
        values.contains(filter_normalized(label, work))
      }
    Conditions(conditions, all~) => {
      for condition in conditions {
        let value = match (condition.value, raw) {
          (Number(_), Text(text)) if !text.trim().is_empty() => {
            work.spend(amount=text.length() + 1)
            numeric_value(Text(text))
          }
          (Text(_), Number(_)) => raw
          (Text(_), _) => Text(filter_normalized(label, work))
          _ => raw
        }
        let matched = condition.matches(value, work)
        if matched != all {
          return matched
        }
      }
      all
    }
  }
}

///|
fn FilterColumn::json(self : FilterColumn) -> Json raise @failure.Failure {
  match self.rule {
    Relative(period, _) =>
      { "kind": "relativeDate", "column": self.column, "period": period }
    Calendar(unit, value) =>
      {
        "kind": "calendar",
        "column": self.column,
        "unit": unit,
        "value": value,
      }
    Color(value, cell_color~) =>
      {
        "kind": "color",
        "column": self.column,
        "cellColor": cell_color,
        "color": value
        .map(value => Json(value.to_upper()))
        .unwrap_or(Json::null()),
      }
    ColorStyle(_, ..) =>
      @failure.reject("invalid-operation", "Color filter style is unresolved")
    Dates(groups, values~, blank~) =>
      {
        "kind": "dates",
        "column": self.column,
        "groups": groups,
        "values": values,
        "blank": blank,
      }
    Average(above~) =>
      { "kind": "average", "column": self.column, "above": above }
    Rank(value, top~, percent~) =>
      {
        "kind": "rank",
        "column": self.column,
        "value": value,
        "top": top,
        "percent": percent,
      }
    Values(values, blank~) =>
      {
        "kind": "values",
        "column": self.column,
        "values": values,
        "blank": blank,
      }
    Custom(conditions, all~) =>
      {
        "kind": "custom",
        "column": self.column,
        "all": all,
        "conditions": conditions.map(c => {
          let value : Json = { "operator": c.operator, "value": c.value }
          value
        }),
      }
  }
}
