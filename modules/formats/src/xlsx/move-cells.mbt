///|
fn Session::move_cells(
  self : Session,
  source_id : String,
  source : String,
  target_id : String,
  destination : String,
) -> Json raise @failure.Failure {
  let from_index = self.sheet_index(source_id)
  let to_index = self.sheet_index(target_id)
  let from = self.sheets[from_index]
  let to = self.sheets[to_index]
  let source = from.merge_target(Range::parse(source))
  let point = Range::parse(destination)
  let target : Range = {
    top: point.top,
    left: point.left,
    bottom: point.top + source.bottom - source.top,
    right: point.left + source.right - source.left,
  }
  ignore(target.name())
  guard target.bottom <= 1048576 &&
    target.right <= 16384 &&
    (source.bottom - source.top + 1).to_int64() *
    (source.right - source.left + 1).to_int64() <=
    4096 else {
    @failure.reject(
      "limit-exceeded", "Cell move exceeds worksheet or 4096-cell bounds",
    )
  }
  if source_id == target_id && source == target {
    return self.query(sheet=Some(target_id), range=Some(target.name()))
  }
  let relocation : CellMove = {
    source_sheet: from.name,
    target_sheet: to.name,
    source,
    target,
  }
  self.check_move_resources()
  for
    (sheet, range) in [
      (from, source),
      (
        {
          ..to,
          merges: to.merges.filter(r => {
            source_id != target_id || !source.covers(r)
          }),
        },
        target,
      ),
    ] {
    let reason = self.format_reason(sheet, range)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    self.check_fill_resources(
      sheet,
      range,
      hyperlinks=true,
      rules=true,
      sparklines=true,
      threads=true,
    )
    ignore(self.hyperlink_at(sheet, range))
    check_merge_markup(Tree::new(sheet.document))
  }
  let sheets = self.sheets.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let targets : Map[Int32, Array[String]] = Map([])
  let source_tree = Tree::new(from.document)
  let mut units = 0L
  let rule_work : RuleShiftWork = {
    cells: 0,
    units: 0,
    fragments: 0,
    source: 0,
    limit: self.budget.entry_bytes.min(4194304),
  }
  for index, original in self.sheets {
    let updates : Map[String, CellContent] = Map([])
    let styles : Map[String, Int32] = Map([])
    let fragments : Map[String, String] = Map([])
    if index == from_index {
      for row in source.top..<=source.bottom {
        for column in source.left..<=source.right {
          let key = Address::{ row, column, }.name()
          updates[key] = { value: Blank, formula: None, keep_shared: false, }
          fragments[key] = ""
        }
      }
    }
    for key, cell in original.cells {
      if (index == from_index && source.contains(cell.address)) ||
        (index == to_index && target.contains(cell.address)) {
        continue
      }
      if cell.formula is Some(formula) {
        let next = move_formula(
          formula,
          relocation,
          Some(original.name),
          Some(original.name),
        )
        if formula != next {
          guard !original.locked && cell.read_only.is_empty() else {
            @failure.reject(
              "protected-content", "A dependent formula is protected",
            )
          }
          updates[key] = {
            value: cell.value,
            formula: Some(next),
            keep_shared: false,
          }
        }
      }
    }
    if index == to_index {
      for row in source.top..<=source.bottom {
        for column in source.left..<=source.right {
          let address : Address = { row, column, }
          let destination = relocation.address(address)
          let cell = from.cells.get(address.name())
          let content : CellContent = {
            value: cell.map(c => c.value).unwrap_or(Blank),
            formula: cell
            .bind(c => c.formula)
            .map(formula => {
              move_formula(formula, relocation, Some(from.name), Some(to.name))
            }),
            keep_shared: false,
          }
          let key = destination.name()
          let markup = from.sorted_cell(
            source_tree, address, destination, content,
          )
          units += markup.length().to_int64()
          guard units <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Moved cell source exceeds budget",
            )
          }
          updates[key] = content
          styles[key] = from.style_at(address)
          fragments[key] = markup
        }
      }
    }
    targets[index] = updates.keys().to_array()
    original.expand_shared_updates(updates)
    let tree = Tree::new(original.document)
    for key, value in updates {
      if !fragments.contains(key) {
        let address = Address::parse(key)
        let markup = original.sorted_cell(tree, address, address, value)
        units += markup.length().to_int64()
        guard units <= 1048576 else {
          @failure.reject("limit-exceeded", "Moved cell source exceeds budget")
        }
        fragments[key] = markup
      }
    }
    let mut document = original.document
    if !updates.is_empty() {
      let (next, edit) = original.prepare(updates, styles~, fragments~)
      document = next
      edits.push((original.id, edit))
    }
    if index == from_index || index == to_index {
      let merges = original.merges.filter(r => {
        !(index == from_index && source.covers(r)) &&
        !(index == to_index && target.covers(r))
      })
      if index == to_index {
        merges.append(
          from.merges
          .filter(r => source.covers(r))
          .map(r => relocation.range(r)),
        )
      }
      guard merges.length() <= 1024 else {
        @failure.reject("limit-exceeded", "Moved merge count exceeds budget")
      }
      if merges != original.merges {
        let (next, edit) = fill_merge_changes(document, merges)
        document = next
        edits.push((original.id, edit))
      }
      document = self.move_notes(
        original, document, from, to, relocation, parts, edits, created,
      )
    }
    document = self.move_hyperlinks(
      original, document, from, to, relocation, parts, edits, created,
    )
    document = move_rules(
      original, document, from, to, relocation, edits, rule_work,
    )
    document = original.move_sparklines(
      document,
      from,
      to,
      relocation,
      edits,
      self.strings,
      self.styles.length(),
    )
    sheets[index] = Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
  }
  let mut workbook = self.workbook
  let names = self.move_names(relocation)
  if !names.is_empty() {
    let (next, edit) = workbook.edit_source(names)
    workbook = next
    edits.push((self.main, edit))
  }
  let calculation = self.calculate(sheets, None, [], workbook, parts~)
  self.validate_inputs(sheets, calculation, targets, false)
  edits.append(self.cache_edits(sheets, calculation))
  let comments = { ..self, sheets, parts, }
  for sheet in sheets {
    comments.check_thread_fallbacks(sheet, comments.read_sheet_threads(sheet))
  }
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    (target_id, target),
    parts~,
    created_parts=created,
  )
  self.query()
}
