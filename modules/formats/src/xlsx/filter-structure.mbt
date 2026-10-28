///|
priv struct FilterPlan {
  states : Map[String, AutoFilterState]
  targets : Array[String]
  hidden : Map[Int32, Bool]
}

///|
fn transformed_filter(
  state : AutoFilterState,
  bounds : Range,
  change : AxisChange?,
) -> AutoFilterState raise @failure.Failure {
  let move_column = fn(column : Int32) -> Int32? {
    if change is Some({ rows: false, .. } as change) {
      change.interval(column, column).map(pair => pair.0)
    } else {
      Some(column)
    }
  }
  let move_row = fn(row : Int32) -> Int32? {
    if change is Some({ rows: true, .. } as change) {
      change.interval(row, row).map(pair => pair.0)
    } else {
      Some(row)
    }
  }
  let settings : FilterSettings = {
    range: bounds.name(),
    columns: state.settings.columns.filter_map(column => {
      move_column(column.column)
      .filter(column => column >= bounds.left && column <= bounds.right)
      .map(next => { ..column, column: next, })
    }),
  }
  ignore(filter_settings(settings))
  let flags : Map[Int32, Array[(String, String)]] = Map([])
  for column, values in state.flags {
    if move_column(column).filter(column => {
        column >= bounds.left && column <= bounds.right
      })
      is Some(next) {
      flags[next] = values
    }
  }
  {
    settings,
    bounds,
    flags,
    tracked: true,
    sort: None,
    manual: state.manual
    .filter_map(move_row)
    .filter(row => row > bounds.top && row <= bounds.bottom),
    filtered: state.filtered
    .filter_map(move_row)
    .filter(row => row > bounds.top && row <= bounds.bottom),
  }
}

///|
fn filter_plan_hidden(
  before : Map[String, AutoFilterState],
  after : Map[String, AutoFilterState],
  change : AxisChange?,
) -> Map[Int32, Bool] {
  let hidden : Map[Int32, Bool] = Map([])
  let manual : Map[Int32, Bool] = Map([])
  for state in before.values() {
    for row in state.manual {
      let next = if change is Some({ rows: true, .. } as change) {
        change.interval(row, row).map(pair => pair.0)
      } else {
        Some(row)
      }
      if next is Some(next) {
        manual[next] = true
      }
    }
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      let next = if change is Some({ rows: true, .. } as change) {
        change.interval(row, row).map(pair => pair.0)
      } else {
        Some(row)
      }
      if next is Some(next) {
        hidden[next] = false
      }
    }
  }
  for state in after.values() {
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = false
    }
  }
  for row in manual.keys() {
    hidden[row] = true
  }
  for row in filter_hidden_rows(after).keys() {
    hidden[row] = true
  }
  hidden
}

///|
fn Session::resize_filter_plan(
  self : Session,
  table : StructuredTable,
  range : Range,
) -> FilterPlan? raise @failure.Failure {
  guard table.filter
    .map(state => {
      state.tracked ||
      !state.settings.columns.is_empty() ||
      !state.flags.is_empty() ||
      state.sort is Some(_)
    })
    .unwrap_or(false) else {
    return None
  }
  let sheet = self.sheets[self.sheet_index(table.sheet)]
  let before = self.sheet_filters(sheet, self.parts)
  let states = before.copy()
  let bounds : Range = { ..range, bottom: range.bottom - table.totals, }
  let state = transformed_filter(before[table.part], bounds, None)
  let previous_hidden = filter_hidden_rows(before)
  let manual = state.manual.copy()
  for row in (bounds.top + 1)..<=bounds.bottom {
    if sheet.dimensions.rows.size(row) == 0 &&
      !previous_hidden.contains(row) &&
      !manual.contains(row) {
      manual.push(row)
    }
  }
  manual.sort()
  states[table.part] = { ..state, manual, }
  Some({
    states,
    targets: [table.part],
    hidden: filter_plan_hidden(before, states, None),
  })
}

///|
fn Session::write_filter_plan(
  self : Session,
  current : Sheet,
  plan : FilterPlan,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> @xml.Document raise @failure.Failure {
  for target in plan.targets {
    if plan.states.get(target) is Some(state) {
      let document = if target == current.id {
        current.document
      } else {
        parts.get(target).unwrap_or_else(() => self.part_xml(target))
      }
      let tree = Tree::new(document)
      let root = tree.root(
        if target == current.id {
          "worksheet"
        } else {
          "table"
        },
      )
      let sort = tree
        .one(root.id, "autoFilter")
        .bind(filter => read_sort_state(tree, filter.id))
        .filter(sort => state.bounds.covers(sort.bounds))
      plan.states[target] = { ..state, sort, }
    }
  }
  self.write_filters(
    current,
    plan.states,
    plan.targets,
    plan.hidden,
    parts,
    edits,
  )
}

///|
fn Session::reapply_candidate_filters(
  self : Session,
  index : Int32,
  states : Map[String, AutoFilterState],
  targets : Array[String],
  sheets : Array[Sheet],
  workbook : @xml.Document,
  calculation : Calculation,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Calculation raise @failure.Failure {
  let candidate : Session = {
    ..self,
    sheets,
    workbook,
    parts,
    calculation: Some(calculation),
  }
  for target in targets {
    if states.get(target) is Some(state) {
      states[target] = {
        ..state,
        filtered: candidate.filtered_rows(index, state.settings),
      }
    }
  }
  let hidden : Map[Int32, Bool] = Map([])
  for state in states.values() {
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = false
    }
  }
  for row in filter_hidden_rows(states).keys() {
    hidden[row] = true
  }
  let current = sheets[index]
  let document = self.write_filters(
    current, states, targets, hidden, parts, edits,
  )
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  if calculation.visibility_dependent() ||
    targets.any(target => target != current.id) {
    self.calculate(sheets, None, [], workbook, parts~)
  } else {
    calculation
  }
}
