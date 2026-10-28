///|
pub(all) struct ConsolidateSource {
  sheet : String
  range : String
}

///|
pub(all) struct ConsolidateSettings {
  sources : Array[ConsolidateSource]
  target : String
  operation : String
  leftLabels : Bool
}

///|
priv struct ConsolidatePlan {
  target : Range
  edit : CellEditPlan
  changed : Bool
  overwritten : Int32
}

///|
fn Session::consolidate_plan(
  self : Session,
  sheet : String,
  settings : ConsolidateSettings,
) -> ConsolidatePlan raise @failure.Failure {
  guard !settings.sources.is_empty() &&
    settings.sources.length() <= 32 &&
    ["sum", "count", "average", "max", "min"].contains(settings.operation) else {
    @failure.reject(
      "invalid-operation", "Consolidation requires 1 to 32 sources and a supported function",
    )
  }
  let origin = Address::parse(settings.target)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let areas = settings.sources.map(source => {
    (self.sheet_index(source.sheet), Range::parse(source.range))
  })
  let labels : Map[String, Int32] = Map([])
  let references : Map[(Int32, Int32), Array[String]] = Map([])
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin,
    names: self.formula_names(),
  }
  let mut cells = 0L
  let mut height = 0
  let mut width = 0
  let mut units = 0
  for (source_index, area) in areas {
    let source = self.sheets[source_index]
    cells += (area.bottom - area.top + 1).to_int64() *
      (area.right - area.left + 1).to_int64()
    guard cells <= 65536 && (!settings.leftLabels || area.right > area.left) else {
      @failure.reject(
        "limit-exceeded", "Consolidation sources exceed 65536 cells or lack a label value column",
      )
    }
    width = width.max(area.right - area.left + 1)
    let rules = if settings.leftLabels {
      Some(self.filter_rules(source_index, work))
    } else {
      None
    }
    for row in area.top..<=area.bottom {
      let output_row = if settings.leftLabels {
        let address : Address = { row, column: area.left, }
        let style = rules
          .unwrap()
          .applied(
            self.styles[source.style_at(address)],
            address,
            self.sheets,
            source_index,
            self.calculation.map(c => c.values).unwrap_or(Map([])),
            work,
          )
        guard style.diagnostic.is_empty() else {
          @failure.reject("protected-content", style.diagnostic)
        }
        let label = formatted(
          self.filter_raw(source_index, row, area.left),
          style.format,
          self.date1904,
        )
        work.spend(amount=label.length() + 1)
        if label.is_empty() {
          continue
        }
        if !labels.contains(label) {
          labels[label] = labels.length()
        }
        labels[label]
      } else {
        row - area.top
      }
      height = height.max(output_row + 1)
      guard height.to_int64() * width.to_int64() <= 4096L else {
        @failure.reject(
          "limit-exceeded", "Consolidation output exceeds 4096 cells",
        )
      }
      for
        column in (area.left + (if settings.leftLabels { 1 } else { 0 }))..<=area.right {
        work.spend()
        let values = references.get_or_init((output_row, column - area.left), () => {
          []
        })
        guard values.length() < 255 else {
          @failure.reject(
            "limit-exceeded", "Consolidation cell exceeds 255 references",
          )
        }
        let reference = Expression::Reference(
          Some(source.name),
          { address: { row, column, }, fixed_row: true, fixed_column: true, },
          None,
        ).source()
        units += reference.length() + 1
        guard units <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Consolidation formulas exceed text budget",
          )
        }
        values.push(reference)
      }
    }
  }
  guard height.to_int64() * width.to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Consolidation output exceeds 4096 cells")
  }
  guard height > 0 &&
    origin.row + height - 1 <= 1048576 &&
    origin.column + width - 1 <= 16384 else {
    @failure.reject(
      "invalid-operation", "Consolidation requires nonempty output within worksheet bounds",
    )
  }
  let target : Range = {
    top: origin.row,
    left: origin.column,
    bottom: origin.row + height - 1,
    right: origin.column + width - 1,
  }
  guard !areas.any(area => area.0 == index && area.1.intersects(target)) else {
    @failure.reject(
      "invalid-operation", "Consolidation output overlaps a source",
    )
  }
  guard !current.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Consolidation output intersects merged cells",
    )
  }
  let tree = Tree::new(current.document)
  let mut overwritten = 0
  for cell in current.cells.values() {
    if !target.contains(cell.address) {
      continue
    }
    ignore(
      current.sorted_cell(tree, cell.address, cell.address, {
        value: cell.value,
        formula: cell.formula,
        keep_shared: false,
      }),
    )
    if cell.value != Blank || cell.formula is Some(_) {
      overwritten += 1
    }
  }
  let function = if settings.operation == "count" {
    "COUNTA"
  } else {
    settings.operation.to_upper()
  }
  let updates : Map[String, CellContent] = Map([])
  let row_labels = Map::from_array(
    labels.to_array().map(entry => (entry.1, entry.0)),
  )
  for row in 0..<height {
    for column in 0..<width {
      let key = Address::{
        row: origin.row + row,
        column: origin.column + column,
      }.name()
      let content = if settings.leftLabels && column == 0 {
        cell_content(row_labels[row], true)
      } else {
        match references.get((row, column)) {
          None => cell_content("", true)
          Some(values) =>
            cell_content("=" + function + "(" + values.join(",") + ")", false)
        }
      }
      let previous = current.cells.get(key)
      if previous.map(c => c.value).unwrap_or(Blank) != content.value ||
        previous.bind(c => c.formula) != content.formula {
        updates[key] = content
      }
    }
  }
  {
    target,
    edit: self.prepare_cells(Map([(index, updates)])),
    changed: !updates.is_empty(),
    overwritten,
  }
}

///|
/// Previews linked consolidation output and occupied cells without changing source or history.
pub fn Session::consolidation(
  self : Session,
  revision : Int32,
  sheet : String,
  settings : ConsolidateSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let plan = self.consolidate_plan(sheet, settings)
  {
    "revision": revision,
    "sheet": sheet,
    "target": settings.target,
    "sources": settings.sources.map(source => {
      "sheet": source.sheet,
      "range": source.range,
    }),
    "operation": settings.operation,
    "leftLabels": settings.leftLabels,
    "resultRange": plan.target.name(),
    "overwrittenCells": plan.overwritten,
    "preview": self.cell_plan_values(sheet, plan.target, plan.edit),
  }
}

///|
fn Session::consolidate_cells(
  self : Session,
  sheet : String,
  settings : ConsolidateSettings,
  source_revision : Int32,
  overwrite : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  let plan = self.consolidate_plan(sheet, settings)
  guard overwrite || plan.overwritten == 0 else {
    @failure.reject(
      "overwrite-required", "Confirm replacement of occupied consolidation cells",
    )
  }
  if !plan.changed {
    return self.query()
  }
  let edit = plan.edit
  self.commit(
    edit.sheets,
    self.workbook,
    edit.calculation,
    edit.edits,
    (sheet, plan.target),
    parts=edit.parts,
    created_parts=edit.created_parts,
  )
  self.query()
}
