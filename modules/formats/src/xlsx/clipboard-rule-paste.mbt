///|
fn Session::copied_rule_styles(
  self : Session,
  base : StyleEdit?,
  formats : Array[CellFormat],
) -> (StyleEdit?, Array[Int?]) raise @failure.Failure {
  if formats.is_empty() {
    return (base, [])
  }
  let base = base.unwrap_or({
    indices: Map([]),
    styles: self.styles,
    parts: self.parts.copy(),
    edits: [],
    created_parts: Map([]),
  })
  let rules = self.derive_conditional_styles(formats, parts=base.parts)
  let created = base.created_parts.copy()
  for name, document in rules.created_parts {
    created[name] = document
  }
  for name in created.keys() {
    created[name] = rules.parts[name]
  }
  let edits = base.edits.copy()
  for entry in rules.edits {
    if !created.contains(entry.0) {
      edits.push(entry)
    }
  }
  (
    Some({ ..base, parts: rules.parts, edits, created_parts: created, }),
    rules.indices,
  )
}

///|
fn Session::prepare_copied_rules(
  self : Session,
  plan : CellEditPlan,
  index : Int,
  target : Range,
  conditional : Array[CopiedConditional],
  validations : Array[CopiedValidation],
  styles : Array[Int?],
  replace_validation : Bool,
) -> Unit raise @failure.Failure {
  let sheet = plan.sheets[index]
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let changes = []
  let existing = tree.all(root.id, "conditionalFormatting")
  let mut conditional_changed = !conditional.is_empty()
  for rule in existing {
    let (remove, updates) = clear_rule_changes(tree, rule, target)
    conditional_changed = conditional_changed || remove || !updates.is_empty()
    if remove {
      changes.push(sheet_node_removal(tree, rule))
    } else {
      changes.append(updates)
    }
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: target.top, column: target.left, },
    names: plan.calculation.names,
  }
  let markup = StringBuilder()
  // Candidate priorities are renumbered together after insertion.
  let mut priority = sheet.document
    .nodes()
    .filter(n => n.name == "cfRule")
    .fold(init=0, (last, n) => {
      last.max(natural(n.attribute("priority").unwrap_or(""), 2147483647))
    })
  for i, rule in conditional {
    guard priority < 2147483647 else {
      @failure.reject("limit-exceeded", "Conditional priority exhausted")
    }
    priority += 1
    rule.settings.check(rule.ranges, plan.sheets, index, work)
    markup.write_string(
      "<od:conditionalFormatting xmlns:od=\"\{spreadsheet_uri}\" sqref=\"\{rule.ranges.map(Range::name).join(" ")}\">\{rule.settings.markup(priority,styles[i])}</od:conditionalFormatting>",
    )
  }
  if !markup.is_empty() {
    changes.push(rule_insertion(tree, markup.to_string()))
  }
  if replace_validation {
    let container = tree.one(root.id, "dataValidations")
    let nodes = validation_nodes(tree)
    let mut count = nodes.length()
    let updates = []
    for node in nodes {
      let (remove, edits) = clear_rule_changes(tree, node, target)
      if remove {
        updates.push(sheet_node_removal(tree, node))
        count -= 1
      } else {
        updates.append(edits)
      }
    }
    let additions = StringBuilder()
    for rule in validations {
      rule.settings.check_metadata()
      let first = rule.ranges[0]
      let raw = rule.settings.markup(first)
      let document = @xml.Document::parse(
        @utf8.encode(raw),
        "copied-validation",
        self.budget.xml_depth,
        self.budget.entry_bytes,
      )
      let node = document.nodes()[0]
      let edits = metadata_changes(node, [
        ("sqref", rule.ranges.map(Range::name).join(" ")),
      ])
      let (next, _) = document.edit_source(edits)
      additions.write_string(next.source())
      count += 1
    }
    guard count <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Copied validation count exceeds budget",
      )
    }
    if container is Some(container) {
      if count == 0 {
        changes.push(sheet_node_removal(tree, container))
      } else {
        changes.append(updates)
        if !updates.is_empty() || !additions.is_empty() {
          changes.append(
            metadata_changes(container, [("count", count.to_string())]),
          )
        }
        if !additions.is_empty() {
          changes.push(insertion(container, additions.to_string()))
        }
      }
    } else if !additions.is_empty() {
      changes.push(
        rule_insertion(
          tree,
          "<od:dataValidations xmlns:od=\"\{spreadsheet_uri}\" count=\"\{count}\">\{additions.to_string()}</od:dataValidations>",
        ),
      )
    }
  }
  if changes.is_empty() {
    return
  }
  let (next, edit) = sheet.document.edit_source(join_insertions(changes))
  plan.edits.push((sheet.id, edit))
  let mut document = next
  guard document.nodes().filter(n => n.name == "cfRule").length() <= 4096 else {
    @failure.reject("limit-exceeded", "Copied conditional count exceeds budget")
  }
  let priorities = if conditional_changed {
    shifted_rule_priorities(document)
  } else {
    []
  }
  if !priorities.is_empty() {
    let (next, edit) = document.edit_source(priorities)
    plan.edits.push((sheet.id, edit))
    document = next
  }
  plan.sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    plan.styles.length(),
  )
  let compiled = self.conditional_rules(
    plan.sheets[index],
    index,
    plan.sheets,
    work,
    parts=plan.parts,
  )
  guard compiled.reason.is_empty() else {
    @failure.reject("protected-content", compiled.reason)
  }
  if self.font_context is Some((probe, profile)) {
    for row in target.top..<=target.bottom {
      for column in target.left..<=target.right {
        work.spend()
        let address : Address = { row, column, }
        let value = calculated_cell(
          plan.sheets,
          plan.calculation.values,
          index,
          address,
        )
        if value == Blank || value == Text("") {
          continue
        }
        let style = compiled.applied(
          plan.styles[plan.sheets[index].style_at(address)],
          address,
          plan.sheets,
          index,
          plan.calculation.values,
          work,
        )
        let identity = profile
          .get(style.font)
          .unwrap_or_else(() => {
            @failure.reject(
              "missing-font",
              "Missing copied conditional font: " + style.font,
            )
          })
        ignore(probe.font_index(identity))
      }
    }
  }
}

///|
fn Sheet::has_clipboard_rules(
  self : Sheet,
  target : Range,
  validations : Bool,
) -> Bool raise @failure.Failure {
  let tree = Tree::new(self.document)
  let nodes = tree.all(tree.root("worksheet").id, "conditionalFormatting")
  if validations {
    nodes.append(validation_nodes(tree))
  }
  nodes.any(node => {
    clear_rule_ranges(node.attribute("sqref").unwrap_or("")).any(r => {
      r.intersects(target)
    })
  })
}
