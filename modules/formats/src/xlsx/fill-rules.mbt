///|
fn Session::prepare_fill_rules(
  self : Session,
  plan : CellEditPlan,
  index : Int,
  source : Range,
  target : Range,
) -> Bool raise @failure.Failure {
  let sheet = plan.sheets[index]
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let rules = tree.all(root.id, "conditionalFormatting")
  rules.append(validation_nodes(tree))
  let work : RuleShiftWork = {
    cells: 0,
    units: 0,
    fragments: 0,
    source: 0,
    limit: self.budget.entry_bytes.min(4194304),
  }
  let vertical = source.left == target.left && source.right == target.right
  let stride = if vertical {
    source.bottom - source.top + 1
  } else {
    source.right - source.left + 1
  }
  let first = if vertical { target.top } else { target.left }
  let last = if vertical { target.bottom } else { target.right }
  let origin = if vertical { source.top } else { source.left }
  let start = first - ((first - origin) % stride + stride) % stride
  let changes = []
  let validation_changes = []
  let mut validation_count = 0
  let mut conditional_changed = false
  for rule in rules {
    let conditional = rule.name == "conditionalFormatting"
    let before = clear_rule_ranges(rule.attribute("sqref").unwrap_or(""))
    let seeds = source.clipboard_intersections(before)
    let after = before.map(r => r.without(target)).flatten()
    for axis = start; axis <= last; axis = axis + stride {
      for seed in seeds {
        let moved : Range = if vertical {
          {
            ..seed,
            top: seed.top + axis - origin,
            bottom: seed.bottom + axis - origin,
          }
        } else {
          {
            ..seed,
            left: seed.left + axis - origin,
            right: seed.right + axis - origin,
          }
        }
        // ONLYOFFICE clips conditional tails; validation copies require a complete range.
        if conditional {
          after.append(target.clipboard_intersections([moved]))
        } else if target.covers(moved) {
          after.push(moved)
        }
        guard after.length() <= 4096 else {
          @failure.reject("limit-exceeded", "Filled rule ranges exceed budget")
        }
      }
    }
    let (updates, count) = if after == before {
      ([], 1)
    } else {
      shift_rule_clone_guard(tree, rule)
      transform_rule_changes(
        tree,
        rule,
        after,
        at => Some(at),
        text => text,
        work,
      )
    }
    if conditional {
      conditional_changed = conditional_changed || !updates.is_empty()
      changes.append(updates)
    } else {
      validation_count += count
      validation_changes.append(updates)
    }
  }
  guard validation_count <= 4096 else {
    @failure.reject("limit-exceeded", "Filled validation count exceeds budget")
  }
  if !validation_changes.is_empty() &&
    tree.one(root.id, "dataValidations") is Some(container) {
    if validation_count == 0 {
      changes.push(sheet_node_removal(tree, container))
    } else {
      changes.append(validation_changes)
      changes.append(
        metadata_changes(container, [("count", validation_count.to_string())]),
      )
    }
  }
  if changes.is_empty() {
    return false
  }
  let (next, edit) = sheet.document.edit_source(join_insertions(changes))
  plan.edits.push((sheet.id, edit))
  let mut next = next
  guard next
    .nodes()
    .filter(n => n.uri == spreadsheet_uri && n.name == "cfRule")
    .length() <=
    4096 else {
    @failure.reject("limit-exceeded", "Filled conditional count exceeds budget")
  }
  if conditional_changed {
    let priorities = shifted_rule_priorities(next)
    if !priorities.is_empty() {
      let (updated, edit) = next.edit_source(priorities)
      next = updated
      plan.edits.push((sheet.id, edit))
    }
  }
  plan.sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    next,
    self.strings,
    plan.styles.length(),
  )
  true
}
