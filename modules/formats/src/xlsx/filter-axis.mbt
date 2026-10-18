///|
fn Session::axis_filter_plan(
  self : Session,
  index : Int,
  change : AxisChange,
  tables : Array[AxisTable],
) -> FilterPlan? raise @failure.Failure {
  let current = self.sheets[index]
  if change.band is Some(_) {
    guard read_filter(current) is None else {
      @failure.reject(
        "protected-content", "Cell shifts on filtered worksheets require filter range support",
      )
    }
    return None
  }
  let before = self.sheet_filters(current, self.parts)
  let states : Map[String, AutoFilterState] = Map([])
  let targets : Array[String] = []
  let mut changed = false
  for part, state in before {
    let native = tables.iter().find_first(plan => plan.before.part == part)
    let bounds = if native is Some(plan) {
      plan.after.map(table => Range::{
        ..table.range,
        bottom: table.range.bottom - table.totals,
      })
    } else {
      change.range(state.bounds).filter(bounds => bounds.bottom > bounds.top)
    }
    let active = part == current.id ||
      native
      .map(plan => {
        plan.before.filter
        .map(state => {
          state.tracked ||
          !state.settings.columns.is_empty() ||
          !state.flags.is_empty() ||
          state.sort is Some(_)
        })
        .unwrap_or(false)
      })
      .unwrap_or(false)
    let affected = bounds != Some(state.bounds) ||
      change.first <=
      (if change.rows { state.bounds.bottom } else { state.bounds.right })
    if active && affected {
      changed = true
      if part == current.id || bounds is Some(_) {
        targets.push(part)
      }
      if change.insert {
        guard change.address({
            row: state.bounds.bottom,
            column: state.bounds.right,
          })
          is Some(_) else {
          @failure.reject(
            "invalid-operation", "Insertion would discard part of the filter range",
          )
        }
      }
    }
    if active && bounds is Some(bounds) {
      if affected {
        states[part] = transformed_filter(state, bounds, Some(change))
      } else {
        states[part] = state
      }
    }
  }
  if !changed {
    return None
  }
  Some({
    states,
    targets,
    hidden: filter_plan_hidden(before, states, Some(change)),
  })
}
