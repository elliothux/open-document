///|
priv struct AxisFilterPlan {
  next : AutoFilterState?
  hidden : Map[Int, Bool]
}

///|
fn Session::axis_filter_plan(
  self : Session,
  index : Int,
  change : AxisChange,
) -> AxisFilterPlan? raise @failure.Failure {
  guard read_filter(self.sheets[index]) is Some(old) else { return None }
  guard change.band is None else {
    @failure.reject(
      "protected-content", "Cell shifts on filtered worksheets require filter range support",
    )
  }
  let last = if change.rows { old.bounds.bottom } else { old.bounds.right }
  if change.first > last {
    return None
  }
  if change.insert {
    guard change.address({ row: old.bounds.bottom, column: old.bounds.right, })
      is Some(_) else {
      @failure.reject(
        "invalid-operation", "Insertion would discard part of the filter range",
      )
    }
  }
  let (manual, filtered) = self.filter_provenance(index, old)
  let move_row = fn(row : Int) -> Int? {
    if change.rows {
      change.interval(row, row).map(pair => pair.0)
    } else {
      Some(row)
    }
  }
  let hidden : Map[Int, Bool] = Map([])
  for row in (old.bounds.top + 1)..<=old.bounds.bottom {
    if move_row(row) is Some(next) {
      hidden[next] = manual.contains(row)
    }
  }
  let next = change
    .range(old.bounds)
    .filter(bounds => bounds.bottom > bounds.top)
    .map(bounds => {
      let move_column = fn(column : Int) -> Int? {
        if change.rows {
          Some(column)
        } else {
          change.interval(column, column).map(pair => pair.0)
        }
      }
      let settings : FilterSettings = {
        range: bounds.name(),
        columns: old.settings.columns.filter_map(column => {
          move_column(column.column).map(next => { ..column, column: next, })
        }),
      }
      ignore(filter_settings(settings))
      let manual = manual
        .filter_map(move_row)
        .filter(row => row > bounds.top && row <= bounds.bottom)
      let filtered = filtered
        .filter_map(move_row)
        .filter(row => row > bounds.top && row <= bounds.bottom)
      let flags : Map[Int, Array[(String, String)]] = Map([])
      for column, values in old.flags {
        if move_column(column) is Some(next) {
          flags[next] = values
        }
      }
      for row in (bounds.top + 1)..<=bounds.bottom {
        hidden[row] = manual.contains(row) || filtered.contains(row)
      }
      { settings, bounds, manual, filtered, tracked: true, flags, sort: None, }
    })
  Some({ next, hidden, })
}

///|
fn axis_filter_write(
  current : Sheet,
  plan : AxisFilterPlan,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(current.document)
  let next = plan.next.map(state => {
    let sort = tree
      .one(tree.root("worksheet").id, "autoFilter")
      .bind(node => read_sort_state(tree, node.id))
      .filter(sort => state.bounds.covers(sort.bounds))
    { ..state, sort, }
  })
  filter_write(current, next, plan.hidden)
}

///|
fn Session::reapply_candidate_filter(
  self : Session,
  index : Int,
  state : AutoFilterState,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  calculation : Calculation,
  edits : Array[(String, @xml.Edit)],
) -> Calculation raise @failure.Failure {
  let candidate : Session = {
    ..self,
    sheets,
    workbook,
    calculation: Some(calculation),
  }
  let filtered = candidate.filtered_rows(index, state.settings)
  let hidden : Map[Int, Bool] = Map([])
  for row in (state.bounds.top + 1)..<=state.bounds.bottom {
    hidden[row] = state.manual.contains(row) || filtered.contains(row)
  }
  let current = sheets[index]
  let (document, edit) = filter_write(
    current,
    Some({ ..state, filtered, }),
    hidden,
  )
  edits.push((current.id, edit))
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  if calculation.visibility_dependent() {
    Calculation::build(sheets, None, [], self.date1904, workbook)
  } else {
    calculation
  }
}
