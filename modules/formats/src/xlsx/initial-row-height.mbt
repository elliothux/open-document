///|
fn Session::initial_row_dimensions(
  self : Session,
  sheet : Sheet,
  dimensions : Dimensions,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Dimensions raise @failure.Failure {
  let dimensions = {
    ..dimensions,
    rows: {
      ..dimensions.rows,
      default_size: self.default_row_height(sheet, probe, profile),
    },
  }
  let rows : Map[Int32, Bool] = Map([])
  // Non-custom heights are caches; measure them with the current font profile.
  for row, cached in sheet.dimensions.automatic_rows {
    if cached && dimensions.rows.size(row) > 0 {
      rows[row] = true
    }
  }
  for cell in sheet.cells.values() {
    let row = cell.address.row
    if sheet.dimensions.automatic_rows.get(row) == Some(false) &&
      dimensions.rows.size(row) > 0 {
      rows[row] = true
    }
  }
  if rows.is_empty() {
    return dimensions
  }
  guard self.calculation is Some(calculation) else { return dimensions }
  let work : FitWork = {
    axes: 0,
    cells: 0,
    units: 0,
    formulas: {
      remaining: 1048576,
      date1904: self.date1904,
      random: None,
      origin: { row: 1, column: 1, },
      names: self.formula_names(),
    },
  }
  let sizes = self.fit_sizes(
    sheet,
    self.sheets,
    self.sheet_index(sheet.id),
    calculation,
    self.styles,
    rows.keys().to_array(),
    probe,
    profile,
    work,
    rows=true,
    reading=true,
  ) catch {
    // Unsupported source keeps its cached geometry and existing cell diagnostics.
    @failure.Failure(code="protected-content", ..) => return dimensions
    error => raise error
  }
  let spans = dimensions.rows.spans.filter(span => !sizes.contains(span.first))
  for row, size in sizes {
    if size != dimensions.rows.default_size {
      spans.push({ first: row, last: row, size, })
    }
  }
  spans.sort_by((a, b) => a.first.compare(b.first))
  { ..dimensions, rows: { ..dimensions.rows, spans, }, }
}
