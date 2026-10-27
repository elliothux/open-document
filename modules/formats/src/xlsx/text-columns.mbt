///|
pub(all) enum TextColumnSplit {
  Delimited(String)
  Fixed(Array[Int])
}

///|
pub(all) struct TextColumnSettings {
  range : String
  split : TextColumnSplit
  types : Array[String]
  formulas : Bool
}

///|
priv struct TextColumnPlan {
  target : Range
  preview : Array[Array[String]]
  overwritten : Int
  types : Array[String]
  split_columns : Int
  edit : CellEditPlan
  changed : Bool
}

///|
fn Session::text_column_plan(
  self : Session,
  sheet : String,
  settings : TextColumnSettings,
) -> TextColumnPlan raise @failure.Failure {
  let source = Range::parse(settings.range)
  guard source.left == source.right && source.bottom - source.top < 4096 else {
    @failure.reject(
      "invalid-operation", "Text to columns requires at most 4096 cells in one column",
    )
  }
  if settings.split is Fixed(breaks) {
    guard !breaks.is_empty() && breaks.length() < 4096 else {
      @failure.reject(
        "invalid-operation", "Fixed-width splitting requires 1 to 4095 positions",
      )
    }
    let mut previous = 0
    for position in breaks {
      guard position > previous && position <= 65534 else {
        @failure.reject(
          "invalid-operation", "Fixed-width positions must be increasing integers from 1 to 65534",
        )
      }
      previous = position
    }
  }
  let current = self.sheets[self.sheet_index(sheet)]
  guard settings.types.length() <= 4096 && settings.types.all(text_column_type) else {
    @failure.reject("invalid-operation", "Invalid text column types")
  }
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let values : Array[Array[String]] = []
  let mut width = 1
  let mut units = 0
  for row in source.top..<=source.bottom {
    let cell = current.cells.get(Address::{ row, column: source.left, }.name())
    let text = cell
      .bind(c => c.formula)
      .map(f => "=" + f)
      .unwrap_or(cell.map(c => c.value.display()).unwrap_or(""))
    units += text.length()
    guard units <= 1048576 && @xml.valid_text(text) else {
      @failure.reject("limit-exceeded", "Text to columns exceeds input budget")
    }
    let fields = match settings.split {
      Delimited(delimiter) =>
        delimited_rows(text, delimiter, line_breaks=false)[0]
      Fixed(breaks) => fixed_column_fields(text, breaks)
    }
    width = width.max(fields.length())
    guard width * (source.bottom - source.top + 1) <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Text to columns output exceeds worksheet or 4096-cell bounds",
      )
    }
    for field in fields {
      guard field.length() <= 32767 else {
        @failure.reject("limit-exceeded", "Split text exceeds cell text budget")
      }
    }
    values.push(fields)
  }
  guard settings.types.is_empty() || settings.types.length() == width else {
    @failure.reject("invalid-operation", "Select a type for every split column")
  }
  let types = if settings.types.is_empty() {
    Array::make(width, "text")
  } else {
    settings.types
  }
  let columns = types.filter(kind => kind != "skip").length()
  guard columns > 0 && source.left + columns - 1 <= 16384 else {
    @failure.reject(
      "limit-exceeded", "Select at least one output column within worksheet bounds",
    )
  }
  let target = { ..source, right: source.left + columns - 1, }
  guard !current.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Text to columns cannot intersect merged cells",
    )
  }
  let tree = Tree::new(current.document)
  let mut overwritten = 0
  for cell in current.cells.values() {
    if !target.contains(cell.address) {
      continue
    }
    guard cell.read_only.is_empty() else {
      @failure.reject("protected-content", cell.read_only)
    }
    ignore(
      current.sorted_cell(tree, cell.address, cell.address, {
        value: cell.value,
        formula: cell.formula,
        keep_shared: false,
      }),
    )
    if cell.address.column > source.left &&
      (cell.value != Blank || cell.formula is Some(_)) {
      overwritten += 1
    }
  }
  for fields in values {
    while fields.length() < width {
      fields.push("")
    }
  }
  let (edit, changed) = self.prepare_text_columns(
    sheet,
    target,
    values,
    types,
    settings.formulas,
  )
  let preview = self.cell_plan_values(sheet, target, edit)
  { target, preview, overwritten, types, split_columns: width, edit, changed, }
}

///|
/// Previews converted fields and occupied output cells without changing source or history.
pub fn Session::text_columns(
  self : Session,
  revision : Int,
  sheet : String,
  settings : TextColumnSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let plan = self.text_column_plan(sheet, settings)
  let result : Map[String, Json] = {
    "revision": Json(revision),
    "sheet": Json(sheet),
    "range": Json(Range::parse(settings.range).name()),
    "resultRange": Json(plan.target.name()),
    "columns": Json(plan.target.right - plan.target.left + 1),
    "overwrittenCells": Json(plan.overwritten),
    "preview": Json(plan.preview),
    "types": Json(plan.types),
    "formulas": Json(settings.formulas),
    "splitColumns": Json(plan.split_columns),
  }
  match settings.split {
    Delimited(delimiter) => result["delimiter"] = Json(delimiter)
    Fixed(breaks) => result["breaks"] = Json(breaks)
  }
  Json(result)
}

///|
fn Session::split_text_columns(
  self : Session,
  sheet : String,
  settings : TextColumnSettings,
  source_revision : Int,
  overwrite : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  let plan = self.text_column_plan(sheet, settings)
  guard overwrite || plan.overwritten == 0 else {
    @failure.reject(
      "overwrite-required", "Confirm replacement of occupied output cells",
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
