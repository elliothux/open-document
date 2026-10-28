///|
fn CellMove::rule_ranges(
  self : CellMove,
  ranges : Array[Range],
) -> Array[Range] {
  let result = []
  for range in ranges {
    if range.intersects(self.source) {
      result.push(
        self.range({
          top: range.top.max(self.source.top),
          bottom: range.bottom.min(self.source.bottom),
          left: range.left.max(self.source.left),
          right: range.right.min(self.source.right),
        }),
      )
    }
  }
  result
}

///|
fn CellMove::rule_source(self : CellMove, at : Address) -> Address {
  {
    row: at.row + self.source.top - self.target.top,
    column: at.column + self.source.left - self.target.left,
  }
}

///|
fn moved_rule_fragment(
  tree : Tree,
  rule : @xml.Node,
  ranges : Array[Range],
  relocation : CellMove,
  work : RuleShiftWork,
) -> (String, Int32) raise @failure.Failure {
  shift_rule_clone_guard(tree, rule)
  let wrapper = @xml.Document::parse(
    @utf8.encode(
      "<worksheet xmlns=\"\{spreadsheet_uri}\">" +
      style_markup(tree, rule) +
      "</worksheet>",
    ),
    "moved-cell-rule",
    128,
    work.limit,
  )
  let fragment_tree = Tree::new(wrapper)
  let root = fragment_tree.root("worksheet")
  let (changes, count) = transform_rule_changes(
    fragment_tree,
    fragment_tree.children[root.id][0],
    ranges,
    at => Some(relocation.rule_source(at)),
    text => {
      if text.trim().is_empty() {
        return text
      }
      move_formula(
        text,
        relocation,
        Some(relocation.source_sheet),
        Some(relocation.target_sheet),
      )
    },
    work,
  )
  let (next, _) = wrapper.edit_source(changes)
  let next_tree = Tree::new(next)
  let markup = next_tree.children[next_tree.root("worksheet").id]
    .map(node => style_markup(next_tree, node))
    .join("")
  guard markup.length() <= work.limit - work.source else {
    @failure.reject("limit-exceeded", "Moved rule source exceeds budget")
  }
  work.source += markup.length()
  (markup, count)
}

///|
fn move_rules(
  sheet : Sheet,
  document : @xml.Document,
  source : Sheet,
  target : Sheet,
  relocation : CellMove,
  edits : Array[(String, @xml.Edit)],
  work : RuleShiftWork,
) -> @xml.Document raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let validations = validation_nodes(tree)
  let container = tree.one(root.id, "dataValidations")
  let rules = tree.all(root.id, "conditionalFormatting")
  rules.append(validations)
  let changes : Array[@xml.SourceChange] = []
  let validation_changes : Array[@xml.SourceChange] = []
  let mut validation_count = 0
  let mut conditional_changed = false
  for rule in rules {
    let before = clear_rule_ranges(rule.attribute("sqref").unwrap_or(""))
    let after = []
    for range in before {
      let remaining = if sheet.id == source.id {
        range.without(relocation.source)
      } else {
        [range]
      }
      for part in remaining {
        after.append(
          if sheet.id == target.id {
            part.without(relocation.target)
          } else {
            [part]
          },
        )
      }
    }
    let same_sheet = sheet.id == source.id && source.id == target.id
    if same_sheet {
      after.append(relocation.rule_ranges(before))
    }
    guard after.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Moved rule range count exceeds budget")
    }
    let (updates, count) = transform_rule_changes(
      tree,
      rule,
      after,
      at => {
        Some(
          if same_sheet && relocation.target.contains(at) {
            relocation.rule_source(at)
          } else {
            at
          },
        )
      },
      text => {
        if text.trim().is_empty() {
          text
        } else {
          move_formula(text, relocation, Some(sheet.name), Some(sheet.name))
        }
      },
      work,
    )
    if rule.name == "conditionalFormatting" {
      conditional_changed = conditional_changed || !updates.is_empty()
      changes.append(updates)
    } else {
      validation_count += count
      validation_changes.append(updates)
    }
  }
  let validation_additions = StringBuilder()
  if sheet.id == target.id && source.id != target.id {
    let original = Tree::new(source.document)
    let source_rules = original.all(
      original.root("worksheet").id,
      "conditionalFormatting",
    )
    source_rules.append(validation_nodes(original))
    let conditional_additions = StringBuilder()
    for rule in source_rules {
      let ranges = relocation.rule_ranges(
        clear_rule_ranges(rule.attribute("sqref").unwrap_or("")),
      )
      if ranges.is_empty() {
        continue
      }
      let (markup, count) = moved_rule_fragment(
        original, rule, ranges, relocation, work,
      )
      if rule.name == "conditionalFormatting" {
        conditional_additions.write_string(markup)
        conditional_changed = true
      } else {
        validation_additions.write_string(markup)
        validation_count += count
      }
    }
    if !conditional_additions.is_empty() {
      changes.push(rule_insertion(tree, conditional_additions.to_string()))
    }
  }
  guard validation_count <= 4096 else {
    @failure.reject("limit-exceeded", "Moved validation count exceeds budget")
  }
  if container is Some(container) {
    if !validation_changes.is_empty() || !validation_additions.is_empty() {
      if validation_count == 0 {
        changes.push(sheet_node_removal(tree, container))
      } else {
        changes.append(validation_changes)
        changes.append(
          metadata_changes(container, [("count", validation_count.to_string())]),
        )
        if !validation_additions.is_empty() {
          changes.push(insertion(container, validation_additions.to_string()))
        }
      }
    }
  } else if !validation_additions.is_empty() {
    changes.push(
      rule_insertion(
        tree,
        "<od:dataValidations xmlns:od=\"\{spreadsheet_uri}\" count=\"\{validation_count}\">\{validation_additions.to_string()}</od:dataValidations>",
      ),
    )
  }
  if changes.is_empty() {
    return document
  }
  guard !sheet.locked else {
    @failure.reject(
      "protected-content", "A moved or dependent cell rule is protected",
    )
  }
  let (next, edit) = document.edit_source(join_insertions(changes))
  let mut next = next
  edits.push((sheet.id, edit))
  if conditional_changed {
    guard next
      .nodes()
      .filter(n => n.uri == spreadsheet_uri && n.name == "cfRule")
      .length() <=
      4096 else {
      @failure.reject(
        "limit-exceeded", "Moved conditional rule count exceeds budget",
      )
    }
    let priorities = shifted_rule_priorities(next)
    if !priorities.is_empty() {
      let (updated, edit) = next.edit_source(priorities)
      next = updated
      edits.push((sheet.id, edit))
    }
  }
  next
}
