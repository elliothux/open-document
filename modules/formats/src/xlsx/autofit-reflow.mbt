///|
fn CellStyle::measurement_key(
  self : CellStyle,
) -> (String, Double, Bool, String, String, Int, String, Bool) {
  (
    self.font,
    self.size,
    self.wrap,
    self.format,
    self.script,
    self.indent,
    self.horizontal,
    self.shrink,
  )
}

///|
fn intervals_intersect(
  spans : Array[(Int, Int)],
  first : Int,
  last : Int,
) -> Bool {
  for low = 0, high = spans.length(); low < high; {
    let middle = low + (high - low) / 2
    if spans[middle].1 < first {
      continue middle + 1, high
    } else {
      continue low, middle
    }
  } nobreak {
    low < spans.length() && spans[low].0 <= last
  }
}

///|
fn changed_merge_rows(
  before : Array[Range],
  after : Array[Range],
) -> Array[(Int, Int)] {
  let intervals : Array[(Int, Int)] = []
  for range in before {
    if !after.contains(range) {
      intervals.push((range.top, range.bottom))
    }
  }
  for range in after {
    if !before.contains(range) {
      intervals.push((range.top, range.bottom))
    }
  }
  intervals.sort_by((a, b) => a.0.compare(b.0))
  let result : Array[(Int, Int)] = []
  for (first, last) in intervals {
    if result.last() is Some((start, end)) && first <= end + 1 {
      result[result.length() - 1] = (start, end.max(last))
    } else {
      result.push((first, last))
    }
  }
  result
}

///|
fn Sheet::rows_affected_by_width(
  self : Sheet,
  columns : Array[(Int, Int)],
  automatic : Map[Int, Bool],
  rows : Map[Int, Bool],
) -> Unit {
  if columns.is_empty() {
    return
  }
  for cell in self.cells.values() {
    let range = self.cell_range(cell.address)
    if automatic.contains(cell.address.row) &&
      intervals_intersect(columns, range.left, range.right) {
      rows[cell.address.row] = true
    }
  }
}

///|
fn Sheet::apply_fitted_sizes(
  self : Sheet,
  sizes : Map[Int, Double],
  edits : Array[(String, @xml.Edit)],
  strings : Array[(String, Bool)],
  styles : Int,
  rows~ : Bool,
) -> Sheet raise @failure.Failure {
  if sizes.is_empty() {
    return self
  }
  let (document, edit) = self.document.edit_source(
    self.fitted_changes(sizes, rows~),
  )
  if document.source() == self.document.source() {
    return self
  }
  let sheet = Sheet::read(
    self.id,
    self.name,
    self.state,
    document,
    strings,
    styles,
  )
  edits.push((self.id, edit))
  sheet
}

///|
fn Session::reflow_dimensions(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
  styles : Array[CellStyle],
  edits : Array[(String, @xml.Edit)],
  context : (@layout.TextProbe, Map[String, String])?,
  work : FitWork,
  parts : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let old : Map[String, (Int, Sheet)] = Map([])
  for index, sheet in self.sheets {
    old[sheet.id] = (index, sheet)
  }
  let original_work = { ..work.formulas, names: self.formula_names(), }
  for index, candidate in sheets {
    let automatic_rows : Map[Int, Bool] = Map([])
    for row, cached in candidate.dimensions.automatic_rows {
      // An absent height remains a valid automatic declaration for data-only edits.
      if cached || context is Some(_) {
        automatic_rows[row] = true
      }
    }
    let automatic_columns = candidate.dimensions.automatic_columns
    if automatic_rows.is_empty() && automatic_columns.is_empty() {
      continue
    }
    let rows : Map[Int, Bool] = Map([])
    let columns : Map[Int, Bool] = Map([])
    let mark = fn(address : Address, value : Value) {
      if automatic_rows.contains(address.row) {
        rows[address.row] = true
      }
      if value != Blank &&
        !(value is Text(_)) &&
        automatic_columns.any(span => {
          span.0 <= address.column && address.column <= span.1
        }) {
        columns[address.column] = true
      }
    }
    let previous = old.get(candidate.id)
    let rich_before = previous
      .map(entry => entry.1.rich_layout_sources())
      .unwrap_or(Map([]))
    let rich_after = candidate.rich_layout_sources()
    let conditional = self.conditional_rules(
      candidate,
      index,
      sheets,
      work.formulas,
      parts~,
    )
    let old_conditional = previous.map(entry => {
      original_work.remaining = work.formulas.remaining
      let rules = self.conditional_rules(
        entry.1,
        entry.0,
        self.sheets,
        original_work,
      )
      work.formulas.remaining = original_work.remaining
      rules
    })
    for name, cell in candidate.cells {
      let value = calculation.values.get((index, name)).unwrap_or(cell.value)
      let before = previous.bind(entry => entry.1.cells.get(name))
      if before is Some(before) && previous is Some((old_index, old_sheet)) {
        let original = self.calculation
          .bind(item => item.values.get((old_index, name)))
          .unwrap_or(before.value)
        original_work.remaining = work.formulas.remaining
        let original_style = old_conditional
          .unwrap()
          .applied(
            self.styles[old_sheet.style_at(before.address)],
            before.address,
            self.sheets,
            old_index,
            self.calculation.map(c => c.values).unwrap_or(Map([])),
            original_work,
          )
        work.formulas.remaining = original_work.remaining
        let candidate_style = conditional.applied(
          styles[candidate.style_at(cell.address)],
          cell.address,
          sheets,
          index,
          calculation.values,
          work.formulas,
        )
        if original == value &&
          rich_before.get(name) == rich_after.get(name) &&
          before.formula == cell.formula &&
          original_style.measurement_key() == candidate_style.measurement_key() &&
          original_style.diagnostic == candidate_style.diagnostic {
          continue
        }
      }
      mark(cell.address, value)
    }
    if previous is Some((_, previous)) {
      for name, cell in previous.cells {
        if !candidate.cells.contains(name) {
          mark(cell.address, Blank)
        }
      }
      candidate.rows_affected_by_width(
        previous.dimensions.columns.changed_ranges(candidate.dimensions.columns),
        automatic_rows,
        rows,
      )
      if previous.merges != candidate.merges {
        let changed = changed_merge_rows(previous.merges, candidate.merges)
        for row in automatic_rows.keys() {
          if intervals_intersect(changed, row, row) {
            rows[row] = true
          }
        }
      }
    }
    if rows.is_empty() && columns.is_empty() {
      continue
    }
    guard context is Some((probe, profile)) else {
      @failure.reject(
        "missing-font", "Measure automatic dimensions with an explicit font profile before editing",
      )
    }
    let mut current = candidate
    if !columns.is_empty() {
      let sizes = self.fit_sizes(
        current,
        sheets,
        index,
        calculation,
        styles,
        columns.keys().to_array(),
        probe,
        profile,
        work,
        rows=false,
        grow=true,
        parts~,
      )
      let changed : Map[Int, Double] = Map([])
      for axis, size in sizes {
        if size != current.dimensions.columns.size(axis) {
          changed[axis] = size
        }
      }
      current = current.apply_fitted_sizes(
        changed,
        edits,
        self.strings,
        styles.length(),
        rows=false,
      )
      if !changed.is_empty() {
        current.rows_affected_by_width(
          candidate.dimensions.columns.changed_ranges(
            current.dimensions.columns,
          ),
          automatic_rows,
          rows,
        )
      }
    }
    if !rows.is_empty() {
      let sizes = self.fit_sizes(
        current,
        sheets,
        index,
        calculation,
        styles,
        rows.keys().to_array(),
        probe,
        profile,
        work,
        rows=true,
        parts~,
      )
      current = current.apply_fitted_sizes(
        sizes,
        edits,
        self.strings,
        styles.length(),
        rows=true,
      )
    }
    sheets[index] = current
  }
}
