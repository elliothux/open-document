///|
fn Session::edit_filter(
  self : Session,
  sheet : String,
  change : SheetEdit,
  table~ : StructuredTable? = None,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if table is Some(table) {
    ignore(table_edit_tree(table, self.part_xml(table.part)))
  }
  let states = self.sheet_filters(current, self.parts)
  let target = table.map(table => table.part).unwrap_or(sheet)
  let targets = states.keys().to_array()
  if !targets.contains(target) {
    targets.push(target)
  }
  let old = states.get(target)
  let settings = match change {
    SetFilter(settings) => Some(settings)
    ClearFilter => old.map(state => { ..state.settings, columns: [], })
    RemoveFilter => None
    ReapplyFilter => old.map(state => state.settings)
    _ => abort("Invalid filter action")
  }
  let settings = settings.map(settings => {
    ..settings,
    columns: settings.columns.map(column => {
      if column.rule is Relative(period, cache) {
        validate_relative_filter(period, cache)
        {
          ..column,
          rule: Relative(period, Some(self.relative_filter_interval(period))),
        }
      } else if column.rule is Color(_, ..) &&
        old.bind(state => {
          state.settings.columns
          .iter()
          .find_first(c => c.column == column.column)
        })
        is Some(previous) &&
        previous.rule is ColorStyle(_, ..) &&
        self.filter_color(column.rule) == self.filter_color(previous.rule) {
        previous
      } else {
        column
      }
    }),
  })
  if old is None && settings is None {
    return self.query()
  }
  let bounds = settings.map(filter_settings)
  let formatting = self.derive_conditional_styles(
    settings
    .map(s => s.columns.map(c => color_filter_format(c.rule)))
    .unwrap_or([]),
  )
  let manual : Map[Int, Bool] = Map([])
  let previous_filtered : Map[Int, Bool] = Map([])
  for state in states.values() {
    for row in state.manual {
      manual[row] = true
    }
    for row in state.filtered {
      previous_filtered[row] = true
    }
  }
  let hidden : Map[Int, Bool] = Map([])
  if old is Some(state) {
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = manual.contains(row)
    }
  }
  if settings is Some(settings) {
    let bounds = bounds.unwrap()
    if table is Some(table) {
      guard table.headers == 1 &&
        bounds ==
        Range::{ ..table.range, bottom: table.range.bottom - table.totals, } else {
        @failure.reject(
          "invalid-operation", "Table filter range must include its header and data without totals",
        )
      }
    } else {
      guard !self.formula_names().tables.any(table => {
        table.sheet == sheet && bounds.intersects(table.range)
      }) else {
        @failure.reject(
          "invalid-operation", "Use the native table filter for a table range",
        )
      }
    }
    let rows : Array[Int] = []
    for row in (bounds.top + 1)..<=bounds.bottom {
      if current.dimensions.rows.size(row) == 0 &&
        !previous_filtered.contains(row) {
        manual[row] = true
      }
      if manual.contains(row) {
        rows.push(row)
      }
      hidden[row] = false
    }
    states[target] = {
      settings: {
        ..settings,
        columns: settings.columns.mapi((i, column) => {
          if column.rule is Color(_, cell_color~) {
            {
              ..column,
              rule: ColorStyle(formatting.indices[i].unwrap(), cell_color~),
            }
          } else {
            column
          }
        }),
      },
      bounds,
      manual: rows,
      filtered: self.filtered_rows(index, settings),
      tracked: true,
      flags: old.map(state => state.flags).unwrap_or(Map([])),
      sort: old
      .bind(state => state.sort)
      .bind(sort => if bounds.covers(sort.bounds) { Some(sort) } else { None }),
    }
  } else {
    ignore(states.remove(target))
  }
  for state in states.values() {
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = false
    }
  }
  for row in manual.keys() {
    if hidden.contains(row) {
      hidden[row] = true
    }
  }
  for row in filter_hidden_rows(states).keys() {
    hidden[row] = true
  }
  let parts = formatting.parts
  let edits = formatting.edits
  let document = self.write_filters(
    current, states, targets, hidden, parts, edits,
  )
  if edits.is_empty() {
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
  let previous = self.calculation.unwrap()
  let calculation = if previous.visibility_dependent() ||
    edits.any(entry => entry.0 != sheet) {
    let calculation = self.calculate(sheets, None, [], self.workbook, parts~)
    if previous.visibility_dependent() {
      edits.append(self.cache_edits(sheets, calculation))
    }
    calculation
  } else {
    previous
  }
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    self.selection,
    parts~,
    created_parts=formatting.created_parts,
  )
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
  parts : Map[String, @xml.Document],
) -> (@xml.Document, Array[(String, @xml.Edit)]) raise @failure.Failure {
  let states = self.sheet_filters(original, parts)
  if !states
    .values()
    .any(state => last > state.bounds.top && first <= state.bounds.bottom) {
    return (document, [])
  }
  let hidden : Map[Int, Bool] = Map([])
  for part in states.keys().to_array() {
    let state = states[part]
    let manual = state.manual.filter(row => row < first || row > last)
    if size == 0 {
      for
        row in first.max(state.bounds.top + 1)..<=last.min(state.bounds.bottom) {
        manual.push(row)
      }
    }
    manual.sort()
    states[part] = { ..state, manual, }
    for row in (state.bounds.top + 1)..<=state.bounds.bottom {
      hidden[row] = false
    }
  }
  for row in filter_hidden_rows(states).keys() {
    hidden[row] = true
  }
  let current = Sheet::read(
    original.id,
    original.name,
    original.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let edits : Array[(String, @xml.Edit)] = []
  let document = self.write_filters(
    current,
    states,
    states.keys().to_array(),
    hidden,
    parts,
    edits,
  )
  (document, edits)
}
