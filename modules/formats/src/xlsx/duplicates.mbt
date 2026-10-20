///|
pub(all) struct DuplicateSettings {
  range : String
  header : Bool
  columns : Array[Int]
}

///|
priv struct DuplicatePlan {
  target : Range
  kept : Array[Int]
  removed : Array[Int]
  preview : Array[Array[String]]
  filter : AutoFilterState?
  table : StructuredTable?
  header : Bool
}

///|
fn Session::duplicate_plan(
  self : Session,
  sheet : String,
  settings : DuplicateSettings,
) -> DuplicatePlan raise @failure.Failure {
  let requested = Range::parse(settings.range)
  let table = self.sorting_table(sheet, requested, true, sparklines=true)
  let target = table.map(table => table.range).unwrap_or(requested)
  let header = table.map(table => table.headers == 1).unwrap_or(settings.header)
  guard (target.bottom - target.top + 1).to_int64() *
    (target.right - target.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Duplicate removal exceeds 4096 cells")
  }
  guard !settings.columns.is_empty() &&
    settings.columns.length() <= target.right - target.left + 1 else {
    @failure.reject(
      "invalid-operation", "Select at least one duplicate comparison column",
    )
  }
  let selected : Map[Int, Bool] = Map([])
  for column in settings.columns {
    guard column >= target.left &&
      column <= target.right &&
      !selected.contains(column) else {
      @failure.reject(
        "invalid-operation", "Duplicate columns must be distinct and inside the range",
      )
    }
    selected[column] = true
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  self.check_reorder_cells(
    current,
    target,
    filter=true,
    tables=self.formula_names().tables.any(table => table.sheet == sheet),
    sparklines=true,
  )
  let filter = if table is Some(_) {
    None
  } else {
    self.sheet_filters(current, self.parts).get(sheet)
  }
  if table is Some(table) {
    ignore(table_edit_tree(table, self.part_xml(table.part)))
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: target.top, column: target.left, },
    names: self.formula_names(),
  }
  let rules = self.filter_rules(index, work)
  let seen : Map[String, Bool] = Map([])
  let kept : Array[Int] = []
  let removed : Array[Int] = []
  let preview : Array[Array[String]] = []
  for
    row in (target.top + (if header { 1 } else { 0 }))..<=(target.bottom -
    table.map(table => table.totals).unwrap_or(0)) {
    let values : Array[String] = []
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let style = rules.applied(
        self.styles[current.style_at(address)],
        address,
        self.sheets,
        index,
        self.calculation.map(c => c.values).unwrap_or(Map([])),
        work,
      )
      guard style.diagnostic.is_empty() else {
        @failure.reject("protected-content", style.diagnostic)
      }
      let value = formatted(
        self.filter_raw(index, row, column),
        style.format,
        self.date1904,
      )
      work.spend(amount=value.length() + 1)
      values.push(value)
    }
    let key = settings.columns
      .map(column => {
        let value = values[column - target.left]
        "\{value.length()}:\{value}"
      })
      .join("")
    if seen.contains(key) {
      removed.push(row)
    } else {
      seen[key] = true
      kept.push(row)
      if preview.length() < 10 {
        preview.push(values)
      }
    }
  }
  let discarded = Map::from_array(removed.map(row => (row, true)))
  let tree = Tree::new(current.document)
  for cell in current.cells.values() {
    if target.contains(cell.address) && discarded.contains(cell.address.row) {
      ignore(
        current.sorted_cell(tree, cell.address, cell.address, {
          value: cell.value,
          formula: cell.formula,
          keep_shared: false,
        }),
      )
    }
  }
  { target, kept, removed, preview, filter, table, header, }
}

///|
/// Previews stable first-occurrence removal using formatted values without changing the workbook.
pub fn Session::duplicates(
  self : Session,
  revision : Int,
  sheet : String,
  settings : DuplicateSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let plan = self.duplicate_plan(sheet, settings)
  let bottom = plan.target.top +
    (if plan.header { 1 } else { 0 }) +
    plan.kept.length() +
    plan.table.map(table => table.totals).unwrap_or(0) -
    1
  {
    "revision": revision,
    "sheet": sheet,
    "range": plan.target.name(),
    "header": plan.header,
    "totalRow": plan.table.map(table => table.totals == 1).unwrap_or(false),
    "columns": settings.columns,
    "keptRows": plan.kept,
    "removedRows": plan.removed,
    "resultRange": { ..plan.target, bottom: bottom.max(plan.target.top), }.name(),
    "preview": plan.preview,
  }
}

///|
fn Session::remove_duplicates(
  self : Session,
  sheet : String,
  settings : DuplicateSettings,
  source_revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  let plan = self.duplicate_plan(sheet, settings)
  if plan.removed.is_empty() {
    return self.query()
  }
  let first = plan.target.top + (if plan.header { 1 } else { 0 })
  let positions = Array::makei(plan.target.bottom - first + 1, i => first + i)
  let order : Array[Int?] = plan.kept.map(row => Some(row))
  if plan.table is Some({ totals: 1, .. }) {
    order.push(Some(plan.target.bottom))
  }
  for _ in plan.removed {
    order.push(None)
  }
  self.reorder_cells(
    sheet,
    plan.target,
    true,
    positions,
    order,
    filter=plan.filter,
    table=plan.table,
  )
}

///|
fn Session::compact_duplicate_table(
  self : Session,
  table : StructuredTable,
  removed : Int,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Range raise @failure.Failure {
  let range = { ..table.range, bottom: table.range.bottom - removed, }
  let source = self.part_xml(table.part)
  let tree = table_edit_tree(table, source)
  self.check_sort_metadata(tree, table=true)
  let root = tree.root("table")
  let changes = metadata_changes(root, [("ref", range.name())])
  let bounds = { ..range, bottom: range.bottom - table.totals, }
  if tree.one(root.id, "sortState") is Some(sort) {
    changes.append(
      resized_sort_state(tree, sort, {
        ..bounds,
        top: bounds.top + table.headers,
      }),
    )
  }
  if tree.one(root.id, "autoFilter") is Some(filter) {
    changes.append(metadata_changes(filter, [("ref", bounds.name())]))
    if tree.one(filter.id, "sortState") is Some(sort) {
      changes.append(resized_sort_state(tree, sort, bounds))
    }
  }
  let (document, edit) = source.edit_source(changes)
  parts[table.part] = document
  edits.push((table.part, edit))
  range
}
