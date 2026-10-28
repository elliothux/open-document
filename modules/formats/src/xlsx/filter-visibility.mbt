///|
fn Session::sheet_filters(
  self : Session,
  sheet : Sheet,
  parts : Map[String, @xml.Document],
) -> Map[String, AutoFilterState] raise @failure.Failure {
  let states : Map[String, AutoFilterState] = Map([])
  if read_filter(sheet) is Some(state) {
    states[sheet.id] = state
  }
  let sheets = self.sheets.copy()
  sheets[self.sheet_index(sheet.id)] = sheet
  for table in self.table_definitions(sheets, self.workbook, parts) {
    if table.sheet != sheet.id {
      continue
    }
    guard table.reason.is_empty() else {
      @failure.reject("protected-content", table.reason)
    }
    if table.filter is Some(state) {
      states[table.part] = state
    }
  }
  let manual : Map[Int32, Bool] = Map([])
  let filtered : Map[Int32, Bool] = Map([])
  let imported : Map[String, Array[Int32]] = Map([])
  let index = self.sheet_index(sheet.id)
  for part, state in states {
    let hidden = if state.tracked {
      state.filtered
    } else {
      // shortcut: Imported overlapping hidden causes are ambiguous; tracked saves retain each filter and the manual mask.
      let hidden = self
        .filtered_rows(index, state.settings)
        .filter(row => sheet.dimensions.rows.size(row) == 0)
      imported[part] = hidden
      hidden
    }
    for row in hidden {
      filtered[row] = true
    }
    for row in state.manual {
      manual[row] = true
    }
  }
  for state in states.values() {
    if !state.tracked {
      for row in (state.bounds.top + 1)..<=state.bounds.bottom {
        if sheet.dimensions.rows.size(row) == 0 && !filtered.contains(row) {
          manual[row] = true
        }
      }
    }
  }
  for part in states.keys().to_array() {
    let state = states[part]
    let rows : Array[Int32] = []
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      guard (sheet.dimensions.rows.size(row) == 0) ==
        (manual.contains(row) || filtered.contains(row)) else {
        @failure.reject(
          "protected-content", "Combined filter visibility no longer matches source rows",
        )
      }
      if manual.contains(row) {
        rows.push(row)
      }
    }
    states[part] = {
      ..state,
      manual: rows,
      filtered: imported.get(part).unwrap_or(state.filtered),
      tracked: true,
    }
  }
  states
}

///|
fn filter_hidden_rows(
  states : Map[String, AutoFilterState],
) -> Map[Int32, Bool] {
  let hidden : Map[Int32, Bool] = Map([])
  for state in states.values() {
    for row in state.manual {
      hidden[row] = true
    }
    for row in state.filtered {
      hidden[row] = true
    }
  }
  hidden
}

///|
fn Session::write_filters(
  self : Session,
  sheet : Sheet,
  states : Map[String, AutoFilterState],
  targets : Array[String],
  hidden : Map[Int32, Bool],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> @xml.Document raise @failure.Failure {
  for part in targets {
    if part == sheet.id {
      continue
    }
    let source = parts.get(part).unwrap_or_else(() => self.part_xml(part))
    let tree = Tree::new(source)
    let changes = filter_source_changes(
      tree,
      tree.root("table"),
      states.get(part),
    )
    if !changes.is_empty() {
      let (document, edit) = source.edit_source(join_insertions(changes))
      if document.source() != source.source() {
        parts[part] = document
        edits.push((part, edit))
      }
    }
  }
  let (document, edit) = filter_write(
    sheet,
    states.get(sheet.id),
    hidden,
    active=states.values().any(state => !state.settings.columns.is_empty()),
  )
  if document.source() == sheet.document.source() {
    return sheet.document
  }
  edits.push((sheet.id, edit))
  document
}
