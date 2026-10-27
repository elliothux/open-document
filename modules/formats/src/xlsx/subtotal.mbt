///|
pub(all) struct SubtotalSettings {
  range : String
  groupColumn : Int
  valueColumn : Int
  operation : String
}

///|
priv struct SubtotalGroup {
  label : String
  first : Int
  last : Int
  total : Int
}

///|
priv struct SubtotalPlan {
  target : Range
  groups : Array[SubtotalGroup]
  workbook : @xml.Document
  edit : CellEditPlan
  edits : Array[(String, @xml.Edit)]
  removed : Map[String, @xml.Document]
  table_edits : Array[String]
  pivot_moves : Map[String, Range]
  preview : Array[Array[String]]
}

///|
fn Session::subtotal_plan(
  self : Session,
  sheet : String,
  settings : SubtotalSettings,
) -> SubtotalPlan raise @failure.Failure {
  let requested = Range::parse(settings.range)
  guard requested.bottom > requested.top &&
    requested.left < requested.right &&
    settings.groupColumn >= requested.left &&
    settings.groupColumn <= requested.right &&
    settings.valueColumn >= requested.left &&
    settings.valueColumn <= requested.right &&
    settings.groupColumn != settings.valueColumn &&
    ["sum", "count", "average"].contains(settings.operation) else {
    @failure.reject(
      "invalid-operation", "Subtotals require a header, data, distinct grouping/value columns and a supported function",
    )
  }
  guard (requested.bottom - requested.top + 1).to_int64() *
    (requested.right - requested.left + 1).to_int64() <=
    4096L else {
    @failure.reject("limit-exceeded", "Subtotal source exceeds 4096 cells")
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let outline = current.outline_axis(true)
  guard !outline.bands.any(band => {
      band.0 <= requested.bottom && band.1 >= requested.top
    }) &&
    (outline.summary_after || outline.bands.is_empty()) &&
    !current.merges.any(merge => merge.intersects(requested)) &&
    !self.formula_names().tables.any(table => {
      table.sheet == sheet && table.range.intersects(requested)
    }) &&
    !self
    .sheet_filters(current, self.parts)
    .values()
    .any(filter => {
      filter.bounds.top <= requested.bottom &&
      filter.bounds.bottom >= requested.top
    }) else {
    @failure.reject(
      "protected-content", "Subtotal source requires an ordinary unmerged range without intersecting outlines, tables or filters",
    )
  }
  let bottom = current.cells
    .values()
    .filter(cell => {
      requested.contains(cell.address) &&
      (cell.value != Blank || cell.formula is Some(_))
    })
    .fold(init=requested.top, (bottom, cell) => bottom.max(cell.address.row))
  guard bottom > requested.top else {
    @failure.reject("invalid-operation", "Subtotal source has no data rows")
  }
  let source = { ..requested, bottom, }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: source.top, column: source.left, },
    names: self.formula_names(),
  }
  let rules = self.filter_rules(index, work)
  let groups : Array[SubtotalGroup] = []
  let mut first = source.top + 1
  let mut label = ""
  for row in (source.top + 1)..<=source.bottom {
    let address : Address = { row, column: settings.groupColumn, }
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
    let next = formatted(
      self.filter_raw(index, row, settings.groupColumn),
      style.format,
      self.date1904,
    )
    work.spend(amount=next.length() + 1)
    if row == source.top + 1 {
      label = next
    } else if !next.is_empty() && next != label {
      groups.push({ label, first, last: row - 1, total: row, })
      first = row
      label = next
    }
    guard groups.length() < 200 else {
      @failure.reject("limit-exceeded", "Subtotals exceed 200 groups")
    }
  }
  groups.push({ label, first, last: source.bottom, total: source.bottom + 1, })
  let target = { ..source, bottom: source.bottom + groups.length() + 1, }
  guard target.bottom <= 1048576 &&
    (target.bottom - target.top + 1).to_int64() *
    (target.right - target.left + 1).to_int64() <=
    4096L else {
    @failure.reject(
      "limit-exceeded", "Subtotal result exceeds worksheet or 4096-cell bounds",
    )
  }
  for cell in current.cells.values() {
    if source.contains(cell.address) && cell.formula is Some(formula) {
      work.spend(amount=formula.length() + 1)
      guard !parse_formula(formula).contains_subtotal() else {
        @failure.reject(
          "protected-content", "Select a source without existing subtotal formulas",
        )
      }
    }
  }
  let mut stage : Session = {
    ..self,
    sheets: self.sheets.copy(),
    parts: self.parts.copy(),
    removed: self.removed.copy(),
    diagnostics: self.diagnostics.copy(),
    slicer_scrolls: self.slicer_scrolls.copy(),
    grid: None,
  }
  let edits : Array[(String, @xml.Edit)] = []
  let removed : Map[String, @xml.Document] = Map([])
  let table_edits : Set[String] = Set([])
  let pivot_moves : Map[String, Range] = Map([])
  let mut units = 0L
  let mut cells = 0L
  let mut payload = 0L
  let insert = fn(first : Int) raise @failure.Failure {
    units += stage.workbook.source().length().to_int64() +
      stage.sheets.fold(init=0L, (sum, sheet) => {
        sum + sheet.document.source().length().to_int64()
      }) +
      stage.parts
      .values()
      .fold(init=0L, (sum, part) => sum + part.source().length().to_int64())
    cells += stage.sheets.fold(init=0L, (sum, sheet) => {
      sum + sheet.cells.length().to_int64()
    })
    guard units <= 8388608L && cells <= 1048576L else {
      @failure.reject(
        "limit-exceeded", "Subtotal structural work exceeds budget",
      )
    }
    if stage.prepare_axes(sheet, {
        rows: true,
        first,
        count: 1,
        insert: true,
        band: None,
      })
      is Some(plan) {
      for (_, edit) in plan.edits {
        payload += edit.payload_bytes()
      }
      guard payload <= 4194304L else {
        @failure.reject("limit-exceeded", "Subtotal history exceeds budget")
      }
      edits.append(plan.edits)
      let removed_parts = stage.removed.copy()
      for name, document in plan.removed {
        removed[name] = document
        if stage.opc.names.contains(name.to_lower()) &&
          !removed_parts.contains(name) {
          removed_parts.push(name)
        }
      }
      for name in plan.table_edits {
        table_edits.add(name)
      }
      for name, range in plan.pivot_moves {
        pivot_moves[name] = range
      }
      stage = {
        ..stage,
        sheets: plan.sheets,
        workbook: plan.workbook,
        parts: plan.parts,
        removed: removed_parts,
        calculation: Some(plan.calculation),
        selection: plan.after,
        grid: None,
      }
    }
  }
  for group in groups.rev() {
    insert(group.last + 1)
  }
  insert(target.bottom)
  let groups = groups.mapi((offset, group) => {
    ..group,
    first: group.first + offset,
    last: group.last + offset,
    total: group.total + offset,
  })
  let function = match settings.operation {
    "sum" => 9
    "count" => 3
    _ => 1
  }
  let updates : Map[String, CellContent] = Map([])
  let formats : Map[String, (Int, Int)] = Map([])
  let current = stage.sheets[index]
  let total = fn(
    row : Int,
    label : String,
    first : Int,
    last : Int,
  ) raise @failure.Failure {
    let label_address : Address = { row, column: settings.groupColumn, }
    let value_address : Address = { row, column: settings.valueColumn, }
    let label_key = label_address.name()
    let value_key = value_address.name()
    let reference = Expression::Reference(
      None,
      {
        address: { row: first, column: settings.valueColumn, },
        fixed_row: true,
        fixed_column: true,
      },
      Some({
        address: { row: last, column: settings.valueColumn, },
        fixed_row: true,
        fixed_column: true,
      }),
    ).source()
    updates[label_key] = cell_content(label, true)
    updates[value_key] = cell_content(
      "=SUBTOTAL(\{function},\{reference})",
      false,
    )
    formats[label_key] = (current.style_at(label_address), 0)
    formats[value_key] = (current.style_at(value_address), 0)
  }
  for group in groups {
    total(
      group.total,
      if group.label.is_empty() {
        "Total"
      } else {
        group.label + " Total"
      },
      group.first,
      group.last,
    )
  }
  total(target.bottom, "Grand Total", source.top + 1, target.bottom - 1)
  let formatting = stage.derive_formats(formats, [
    CellFormat::new(bold=Some(true)),
  ])
  let edit = stage.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, formatting.indices)]),
    formatting=Some(formatting),
  )
  edits.append(edit.edits)
  let current = edit.sheets[index]
  let metadata : Map[Int, Array[(String, String)]] = Map([])
  for group in groups {
    for row in group.first..<=group.last {
      outline_put(metadata, row, "outlineLevel", "2")
    }
    for
      (name, value) in [
        ("outlineLevel", "1"),
        ("hidden", "0"),
        ("collapsed", "0"),
      ] {
      outline_put(metadata, group.total, name, value)
    }
  }
  for
    (name, value) in [
      ("outlineLevel", "0"),
      ("hidden", "0"),
      ("collapsed", "0"),
    ] {
    outline_put(metadata, target.bottom, name, value)
  }
  let changes = current.outline_metadata(true, metadata) +
    outline_summary_changes(Tree::new(current.document), true, true)
  let (document, outline_edit) = current.document.edit_source(
    join_insertions(changes),
  )
  edits.push((sheet, outline_edit))
  let current = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    edit.styles.length(),
  )
  let maximum = current.outline_axis(true).bands.fold(init=0, (maximum, band) => {
    maximum.max(band.2)
  })
  let (document, level_edit) = current.document.edit_source(
    outline_level_changes(current, true, maximum),
  )
  edits.push((sheet, level_edit))
  edit.sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    edit.styles.length(),
  )
  let preview = stage.cell_plan_values(sheet, target, edit)
  {
    target,
    groups,
    workbook: stage.workbook,
    edit,
    edits,
    removed,
    table_edits: table_edits.to_array(),
    pivot_moves,
    preview,
  }
}

///|
/// Previews adjacent-group subtotal rows, a grand total and outlines without changing source.
pub fn Session::subtotals(
  self : Session,
  revision : Int,
  sheet : String,
  settings : SubtotalSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let plan = self.subtotal_plan(sheet, settings)
  {
    "revision": revision,
    "sheet": sheet,
    "range": settings.range,
    "groupColumn": settings.groupColumn,
    "valueColumn": settings.valueColumn,
    "operation": settings.operation,
    "resultRange": plan.target.name(),
    "grandTotalRow": plan.target.bottom,
    "groups": plan.groups.map(group => {
      (
        {
          "label": group.label,
          "firstRow": group.first,
          "lastRow": group.last,
          "totalRow": group.total,
        } : Json)
    }),
    "preview": plan.preview,
  }
}

///|
fn Session::create_subtotals(
  self : Session,
  sheet : String,
  settings : SubtotalSettings,
  source_revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  let plan = self.subtotal_plan(sheet, settings)
  let edit = plan.edit
  self.commit(
    edit.sheets,
    plan.workbook,
    edit.calculation,
    plan.edits,
    (sheet, plan.target),
    parts=edit.parts,
    created_parts=edit.created_parts,
    removed=plan.removed,
    table_edits=plan.table_edits,
    pivot_moves=plan.pivot_moves,
    drawing_selection=self.drawing_selection,
  )
  self.query()
}
