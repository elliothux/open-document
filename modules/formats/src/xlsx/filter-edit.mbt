///|
fn Session::edit_filter(
  self : Session,
  sheet : String,
  change : SheetEdit,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let old = read_filter(current)
  let settings = match change {
    SetFilter(settings) => Some(settings)
    ClearFilter => old.map(state => { ..state.settings, columns: [], })
    RemoveFilter => None
    ReapplyFilter => old.map(state => state.settings)
    _ => abort("Invalid filter action")
  }
  if old is None && settings is None {
    return self.query()
  }
  let (manual, previous_filtered) = old
    .map(state => self.filter_provenance(index, state))
    .unwrap_or(([], []))
  let hidden : Map[Int, Bool] = Map([])
  if old is Some(state) {
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = manual.contains(row)
    }
  }
  let next = settings.map(settings => {
    let bounds = filter_settings(settings)
    let manual = manual.filter(row => row > bounds.top && row <= bounds.bottom)
    for row in (bounds.top + 1)..<=bounds.bottom {
      if current.dimensions.rows.size(row) == 0 &&
        !previous_filtered.contains(row) &&
        !manual.contains(row) {
        manual.push(row)
      }
    }
    manual.sort()
    let filtered = self.filtered_rows(index, settings)
    for row in (bounds.top + 1)..<=bounds.bottom {
      hidden[row] = manual.contains(row) || filtered.contains(row)
    }
    {
      settings,
      bounds,
      manual,
      filtered,
      tracked: true,
      flags: old.map(state => state.flags).unwrap_or(Map([])),
    }
  })
  let (document, edit) = filter_write(current, next, hidden)
  if document.source() == current.document.source() {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let edits = [(sheet, edit)]
  let previous = self.calculation.unwrap()
  let calculation = if previous.visibility_dependent() {
    let calculation = Calculation::build(
      sheets,
      None,
      [],
      self.date1904,
      self.workbook,
    )
    edits.append(self.cache_edits(sheets, calculation))
    calculation
  } else {
    previous
  }
  self.commit(sheets, self.workbook, calculation, edits, self.selection)
  self.query()
}

///|
fn Session::filter_dimension_changes(
  self : Session,
  original : Sheet,
  document : @xml.Document,
  first : Int,
  last : Int,
  size : Double,
) -> (@xml.Document, Array[(String, @xml.Edit)]) raise @failure.Failure {
  guard read_filter(original) is Some(state) &&
    last > state.bounds.top &&
    first <= state.bounds.bottom else {
    return (document, [])
  }
  let index = self.sheet_index(original.id)
  let (manual, filtered) = self.filter_provenance(index, state)
  let manual = manual.filter(row => row < first || row > last)
  if size == 0 {
    for row in first.max(state.bounds.top + 1)..<=last.min(state.bounds.bottom) {
      manual.push(row)
    }
  }
  manual.sort()
  let current = Sheet::read(
    original.id,
    original.name,
    original.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let hidden : Map[Int, Bool] = Map([])
  for row in (state.bounds.top + 1)..<=state.bounds.bottom {
    hidden[row] = manual.contains(row) || filtered.contains(row)
  }
  let (document, edit) = filter_write(
    current,
    Some({ ..state, manual, filtered, tracked: true, }),
    hidden,
  )
  (document, [(original.id, edit)])
}
