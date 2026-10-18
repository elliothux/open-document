///|
fn Session::merge_cells(
  self : Session,
  id : String,
  range : Range,
  discard : Bool,
  unmerge : Bool,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(id)
  let current = self.sheets[index]
  let target = current.merge_target(range)
  let reason = if unmerge {
    self.unmerge_reason(current, target)
  } else {
    self.merge_reason(current, target)
  }
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let removed = current.merges.filter(merge => merge.intersects(target))
  if (unmerge && removed.is_empty()) ||
    (!unmerge && removed.length() == 1 && removed[0] == target) {
    return self.query()
  }
  guard unmerge || current.merges.length() - removed.length() < 1024 else {
    @failure.reject("limit-exceeded", "Merged range count exceeds budget")
  }
  let notes = if unmerge { None } else { self.read_sheet_notes(current) }
  guard unmerge ||
    discard ||
    (
      current.merge_discarded(target) == 0 &&
      notes.map(n => n.merge_discarded(target)).unwrap_or(0) == 0
    ) else {
    @failure.reject(
      "merge-data-loss", "Merging keeps the upper-left cell and one note; discarding other values, formulas or notes requires explicit discard",
    )
  }
  let plan = if unmerge { None } else { self.merge_formats(current, target) }
  let updates : Map[String, CellContent] = Map([])
  let changed : Array[(Int, Range)] = []
  if !unmerge {
    for key, cell in current.cells {
      if target.contains(cell.address) &&
        !(cell.address.row == target.top && cell.address.column == target.left) &&
        (cell.value != Blank || cell.formula is Some(_)) {
        updates[key] = { value: Blank, formula: None, keep_shared: false, }
        changed.push(
          (
            index,
            {
              top: cell.address.row,
              bottom: cell.address.row,
              left: cell.address.column,
              right: cell.address.column,
            },
          ),
        )
      }
    }
  }
  let mut document = current.document
  let edits : Array[(String, @xml.Edit)] = []
  if !updates.is_empty() {
    current.expand_shared_updates(updates)
    let (next, edit) = current.prepare(updates)
    document = next
    edits.push((id, edit))
  }
  let parts = plan.map(plan => plan.parts).unwrap_or(self.parts).copy()
  let styles = plan.map(plan => plan.styles).unwrap_or(self.styles)
  let created_parts = plan.map(plan => plan.created_parts).unwrap_or(Map([]))
  if plan is Some(plan) {
    let sheet = Sheet::read(
      id,
      current.name,
      current.state,
      document,
      self.strings,
      self.styles.length(),
    )
    let updates : Map[String, CellContent] = Map([])
    for name in plan.indices.keys() {
      updates[name] = { value: Blank, formula: None, keep_shared: true, }
    }
    let (next, edit) = sheet.prepare(
      updates,
      styles=plan.indices,
      preserve_values=true,
    )
    document = next
    edits.append(plan.edits)
    edits.push((id, edit))
  }
  if notes is Some(notes) {
    let kept = notes.merge_note(target)
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      if target.contains(note.address) {
        addresses[note.address.name()] = if kept is Some(kept) &&
          kept.address == note.address {
          Some({ row: target.top, column: target.left, })
        } else {
          None
        }
      }
    }
    update_note_addresses(notes, addresses, parts, edits)
  }
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let container = tree.one(root.id, "mergeCells")
  let changes : Array[@xml.SourceChange] = []
  let count = current.merges.length() -
    removed.length() +
    (if unmerge { 0 } else { 1 })
  let markup = "<od:mergeCell xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{target.name()}\"/>"
  if container is Some(container) {
    if count == 0 {
      changes.push(sheet_node_removal(tree, container))
    } else {
      for node in tree.all(container.id, "mergeCell") {
        if Range::parse(node.attribute("ref").unwrap_or("")).intersects(target) {
          changes.push(sheet_node_removal(tree, node))
        }
      }
      changes.append(
        metadata_changes(container, [("count", count.to_string())]),
      )
      if !unmerge {
        changes.push(insertion(container, markup))
      }
    }
  } else if !unmerge {
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        [
          "phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks",
          "printOptions", "pageMargins", "pageSetup", "headerFooter", "rowBreaks",
          "colBreaks", "customProperties", "cellWatches", "ignoredErrors", "smartTags",
          "drawing", "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects",
          "controls", "webPublishItems", "tableParts", "extLst",
        ].contains(node.name)
      })
    let markup = "<od:mergeCells xmlns:od=\"\{spreadsheet_uri}\" count=\"1\">\{markup}</od:mergeCells>"
    changes.push(
      if next is Some(next) {
        {
          node: root.id,
          offset: next.start - root.start,
          length: 0,
          xml: markup,
        }
      } else {
        insertion(root, markup)
      },
    )
  }
  if !unmerge && tree.one(root.id, "dataValidations") is Some(validations) {
    let rules = tree.all(validations.id, "dataValidation")
    let removed : Array[@xml.Node] = []
    let adjusted : Array[@xml.SourceChange] = []
    for rule in rules {
      let (remove, updates) = clear_rule_changes(
        tree,
        rule,
        target,
        keep_anchor=true,
      )
      if remove {
        removed.push(rule)
      } else {
        adjusted.append(updates)
      }
    }
    guard (removed.is_empty() && adjusted.is_empty()) ||
      tree.children.get(validations.id).unwrap_or([]).length() == rules.length() else {
      @failure.reject(
        "protected-content", "Unknown validation children require merge editing support",
      )
    }
    if removed.length() == rules.length() && !removed.is_empty() {
      changes.push(sheet_node_removal(tree, validations))
    } else {
      changes.append(adjusted)
      for rule in removed {
        changes.push(sheet_node_removal(tree, rule))
      }
      if !removed.is_empty() && validations.attribute("count") is Some(_) {
        changes.append(
          metadata_changes(validations, [
            ("count", (rules.length() - removed.length()).to_string()),
          ]),
        )
      }
    }
  }
  let (document, edit) = document.edit_source(changes)
  edits.push((id, edit))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    current.name,
    current.state,
    document,
    self.strings,
    styles.length(),
  )
  let calculation = if changed.is_empty() {
    self.calculation.unwrap()
  } else {
    self.calculate(sheets, self.calculation, changed, self.workbook)
  }
  if !changed.is_empty() {
    edits.append(
      self.cache_edits(sheets, calculation, style_count=styles.length()),
    )
  }
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    if id == self.selection.0 {
      (id, target)
    } else {
      self.selection
    },
    parts~,
    created_parts~,
  )
  self.query()
}
