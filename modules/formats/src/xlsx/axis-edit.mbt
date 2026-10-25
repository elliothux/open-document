///|
fn Session::edit_axes(
  self : Session,
  id : String,
  change : AxisChange,
) -> Json raise @failure.Failure {
  guard change.first >= 1 &&
    change.first <= change.limit() &&
    change.count >= 1 &&
    change.count <= 4096 &&
    change.count <= change.limit() - change.first + 1 else {
    @failure.reject(
      "invalid-operation", "Invalid structural row or column interval",
    )
  }
  let index = self.sheet_index(id)
  let reason = self.sheet_rename_reason(
    structure=false,
    tables=true,
    sparklines=true,
    pictures=true,
    charts=true,
    analysis=change.band is None,
    threads=true,
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let target = self.sheets[index]
  let notes = self.read_sheet_notes(target, allow_threads=true)
  let threads = self.read_sheet_threads(target)
  guard !target.locked && target.frozen.edit_reason.is_empty() else {
    @failure.reject(
      "protected-content", "Protected worksheet or view prevents structural editing",
    )
  }
  for relation in self.relationships() {
    if relation.owner == id &&
      !["hyperlink", "comments", "vmlDrawing", "table", "drawing"].any(kind => {
        relation.kind == relationship_uri + kind
      }) &&
      relation.kind != thread_relationship_uri + "threadedComment" &&
      !(change.band is None &&
      [
        relationship_uri + "pivotTable",
        slicer_relationship_uri + "slicer",
        timeline_relationship_uri + "Timeline",
      ].contains(relation.kind)) {
      @failure.reject(
        "protected-content", "Worksheet resources require reference-aware structural editing",
      )
    }
  }
  let tree = Tree::new(target.document)
  for node in tree.children.get(tree.root("worksheet").id).unwrap_or([]) {
    guard [
      "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
      "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
      "headerFooter", "sortState", "conditionalFormatting", "dataValidations", "hyperlinks",
      "legacyDrawing", "extLst", "autoFilter", "tableParts", "drawing",
    ].contains(node.name) else {
      @failure.reject(
        "protected-content", "Worksheet metadata requires structural range support",
      )
    }
  }
  let sheets = self.sheets.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let parts = self.parts.copy()
  let removed : Map[String, @xml.Document] = Map([])
  let pivot_moves = if change.band is None {
    self.axis_analysis(target, change, parts, edits)
  } else {
    Map([])
  }
  let tables = self.axis_tables(target, change, parts, edits)
  let filter = self.axis_filter_plan(index, change, tables)
  if notes is Some(notes) {
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      let next = change.address(note.address)
      guard !change.insert || next is Some(_) else {
        @failure.reject(
          "invalid-operation", "Insertion would discard a cell note",
        )
      }
      addresses[note.address.name()] = next
    }
    update_note_addresses(notes, addresses, parts, edits, threaded=true)
    update_thread_addresses(threads, addresses, parts, edits)
  }
  let rule_work : RuleShiftWork = {
    cells: 0,
    units: 0,
    fragments: 0,
    source: 0,
    limit: self.budget.entry_bytes.min(4194304),
  }
  for i, original in sheets {
    let updates : Map[String, CellContent] = Map([])
    let source = Tree::new(original.document)
    for name, cell in original.cells {
      if cell.formula is Some(formula) {
        let text = axis_formula(
          formula,
          Some(original.name),
          target.name,
          change,
        )
        let moved = original.id == id &&
          change.address(cell.address) != Some(cell.address)
        if text != formula || (moved && cell.group is Some(_)) {
          updates[name] = {
            value: cell.value,
            formula: Some(text),
            keep_shared: false,
          }
        }
      }
    }
    let mut document = original.document
    if !updates.is_empty() {
      original.expand_shared_updates(updates)
      for name in updates.keys() {
        let node = source.one(original.cells[name].node, "f").unwrap()
        guard source.children.get(node.id).unwrap_or([]).is_empty() &&
          node.attributes.all(a => {
            a.uri.is_empty() && ["t", "ref", "si"].contains(a.name)
          }) &&
          !original.document.source()[node.opening_end:node.closing_start].contains(
            "<",
          ) else {
          @failure.reject(
            "protected-content", "Unknown shared formula metadata prevents structural editing",
          )
        }
      }
      let (next, edit) = original.prepare(updates)
      document = next
      edits.push((original.id, edit))
    }
    let current = Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
    let (metadata, split_rules) = axis_sheet_metadata(
      current,
      target.name,
      change,
      rule_work,
    )
    if !metadata.is_empty() {
      let (next, edit) = document.edit_source(metadata)
      document = next
      edits.push((original.id, edit))
    }
    if split_rules {
      let priorities = shifted_rule_priorities(document)
      if !priorities.is_empty() {
        let (next, edit) = document.edit_source(priorities)
        document = next
        edits.push((original.id, edit))
      }
    }
    if original.id == id {
      let current = Sheet::read(
        original.id,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
      let changes = if change.band is Some(_) {
        current.shift_cells(change, self.budget.entry_bytes.min(4194304))
      } else {
        current.axis_cells(change)
      }
      if !changes.is_empty() {
        let (next, edit) = document.edit_source(changes)
        document = next
        edits.push((id, edit))
      }
      if filter is Some(plan) {
        let current = Sheet::read(
          original.id,
          original.name,
          original.state,
          document,
          self.strings,
          self.styles.length(),
        )
        document = self.write_filter_plan(current, plan, parts, edits)
      }
      let (next, outline_edits) = self.axis_outline(
        original, document, change, parts,
      )
      document = next
      edits.append(outline_edits)
      let current = Sheet::read(
        original.id,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
      document = self.axis_table_resources(
        current, tables, parts, edits, removed,
      )
    }
    sheets[i] = Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
  }
  let mut workbook = self.workbook
  let names = self.axis_names(target.name, change)
  if !names.is_empty() {
    let (next, edit) = workbook.edit_source(names)
    workbook = next
    edits.push((self.main, edit))
  }
  workbook = self.table_reference_removals(
    sheets,
    workbook,
    tables
    .filter(plan => !plan.removed.is_empty() || plan.after is None)
    .map(plan => {
      (plan.after.unwrap_or(plan.before), plan.removed, plan.after is None)
    }),
    tables.filter_map(plan => plan.after),
    parts,
    edits,
  )
  let (table_sheet, table_cells) = self.axis_table_cells(
    sheets[index],
    tables,
    change,
    edits,
  )
  sheets[index] = table_sheet
  self.axis_chart_references(target.name, change, parts, edits)
  let after = if change.band is Some((first, last)) {
    (
      id,
      if change.rows {
        {
          top: change.first,
          bottom: change.first + change.count - 1,
          left: first,
          right: last,
        }
      } else {
        {
          top: first,
          bottom: last,
          left: change.first,
          right: change.first + change.count - 1,
        }
      },
    )
  } else if self.selection.0 == id {
    let selected = self.selection.1
    let range = change
      .range(selected)
      .unwrap_or_else(() => {
        let point = change.position({
          row: selected.top,
          column: selected.left,
        })
        {
          top: point.row,
          bottom: point.row,
          left: point.column,
          right: point.column,
        }
      })
    (id, range)
  } else {
    self.selection
  }
  if edits.is_empty() {
    return self.query()
  }
  let removed_parts = self.removed.copy()
  for part in removed.keys() {
    if self.opc.names.contains(part.to_lower()) {
      removed_parts.push(part)
    }
  }
  let mut calculation = self.calculate(
    sheets,
    None,
    [],
    workbook,
    parts~,
    removed=removed_parts,
  )
  if filter is Some(plan) && !plan.targets.is_empty() {
    let candidate : Session = {
      ..self,
      sheets,
      workbook,
      parts,
      removed: removed_parts,
      calculation: Some(calculation),
    }
    calculation = candidate.reapply_candidate_filters(
      index,
      candidate.sheet_filters(sheets[index], parts),
      plan.targets,
      sheets,
      workbook,
      calculation,
      parts,
      edits,
    )
  }
  if !table_cells.is_empty() {
    self.validate_inputs(
      sheets,
      calculation,
      Map([(index, table_cells)]),
      false,
    )
  }
  self.axis_pictures(
    target,
    sheets[index],
    change,
    {
      ..self,
      sheets,
      workbook,
      parts,
      calculation: Some(calculation),
      removed: removed_parts,
    },
    parts,
    edits,
    analysis=change.band is None,
  )
  if change.band is None {
    ignore({ ..self, sheets, workbook, parts, }.analysis_parts())
  }
  edits.append(self.cache_edits(sheets, calculation))
  let comments = { ..self, sheets, workbook, parts, }
  comments.check_thread_fallbacks(
    sheets[index],
    comments.read_sheet_threads(sheets[index]),
  )
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    after,
    parts~,
    removed~,
    table_edits=tables.map(plan => plan.before.part),
    drawing_selection=self.drawing_selection,
    pivot_moves~,
  )
  self.query()
}
