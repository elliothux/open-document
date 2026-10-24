///|
fn Session::pivot_source_headers(
  self : Session,
  settings : PivotSettings,
  unique~ : Bool = false,
) -> Array[String] raise @failure.Failure {
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  let range = settings.validate()
  let index = self.sheet_index(settings.sourceSheet)
  let sheet = self.sheets[index]
  let calculation = self.calculation.unwrap()
  let headers : Array[String] = []
  for column in range.left..<=range.right {
    let address = Address::{ row: range.top, column, }
    let key = address.name()
    let cell = sheet.cells.get(key)
    guard cell
      .map(cell => {
        cell.calculation_supported &&
        (cell.formula is None || calculation.expressions.contains((index, key)))
      })
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "Pivot source requires current supported formula values",
      )
    }
    let value = calculation.values
      .get((index, key))
      .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
    let label = formatted(
      value,
      self.styles[sheet.style_at(address)].format,
      self.date1904,
    )
    guard !label.trim().is_empty() &&
      label.length() <= 255 &&
      @xml.valid_text(label) &&
      !(value is Error(_)) else {
      @failure.reject(
        "invalid-operation", "Pivot fields require nonempty source headers",
      )
    }
    guard !unique || !headers.any(name => name.to_lower() == label.to_lower()) else {
      @failure.reject(
        "protected-content", "Linked source headers must identify unique fields",
      )
    }
    let mut name = label
    let mut suffix = 2
    while headers.contains(name) {
      name = label + suffix.to_string()
      suffix += 1
    }
    guard name.length() <= 255 else {
      @failure.reject("limit-exceeded", "Pivot field name exceeds budget")
    }
    headers.push(name)
  }
  headers
}

///|
fn pivot_source_field(
  headers : Array[String],
  name : String,
) -> Int raise @failure.Failure {
  headers
  .search_by(header => header == name)
  .unwrap_or_else(() => {
    @failure.reject(
      "protected-content",
      "A linked pivot or analysis control still uses the removed source field: " +
      name,
    )
  })
}

///|
fn PivotSettings::remap_source_fields(
  self : PivotSettings,
  previous : Array[String],
  headers : Array[String],
) -> PivotSettings raise @failure.Failure {
  let field = (index : Int) => pivot_source_field(headers, previous[index])
  {
    ..self,
    rows: self.rows.map(field),
    columns: self.columns.map(field),
    subtotals: self.subtotals.map(field),
    filters: self.filters.map(filter => {
      ..filter,
      field: field(filter.field),
    }),
    numberGroups: self.numberGroups.map(group => {
      ..group,
      field: field(group.field),
    }),
    dateGroups: self.dateGroups.map(group => {
      ..group,
      field: field(group.field),
    }),
    values: self.values.map(value => {
      ..value,
      field: field(value.field),
      baseField: value.baseField.map(field),
    }),
  }
}
