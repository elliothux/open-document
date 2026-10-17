///|
fn text_column_type(kind : String) -> Bool {
  ["text", "general", "ymd", "mdy", "dmy", "skip"].contains(kind)
}

///|
fn text_column_date(
  text : String,
  order : String,
  date1904 : Bool,
) -> (Value, String) {
  let tokens = text
    .trim()
    .to_owned()
    .to_upper()
    .replace_all(old="T", new=" ")
    .split(" ")
    .filter(s => !s.is_empty())
    .map(s => s.to_owned())
    .to_array()
  if tokens.is_empty() {
    return (Text(text), "")
  }
  let parts = tokens[0]
    .replace_all(old="/", new="-")
    .replace_all(old=".", new="-")
    .split("-")
    .map(s => s.to_owned())
    .to_array()
  guard parts.length() == 3 && parts.all(s => date_integer(s) is Some(_)) else {
    return (Text(text), "")
  }
  let (year, month, day) = match order {
    "ymd" => (parts[0], parts[1], parts[2])
    "mdy" => (parts[2], parts[0], parts[1])
    _ => (parts[2], parts[1], parts[0])
  }
  guard year.length() == 4 else { return (Text(text), "") }
  let tail = tokens[1:].to_owned().join(" ")
  let value = formula_date_text(
    year +
    "-" +
    month +
    "-" +
    day +
    (if tail.is_empty() { "" } else { " " + tail }),
    date1904,
  )
  if value is Number(_) {
    (value, if tail.is_empty() { "yyyy-mm-dd" } else { "yyyy-mm-dd hh:mm:ss" })
  } else {
    (Text(text), "")
  }
}

///|
fn text_column_content(
  text : String,
  kind : String,
  formulas : Bool,
  date1904 : Bool,
) -> (CellContent, String) raise @failure.Failure {
  if text.is_empty() {
    return (cell_content("", true), "")
  }
  if kind == "general" {
    if formulas && text.has_prefix("=") {
      return (cell_content(text, false), "")
    }
    let value = input_value(text, literal=false)
    if value is Number(_) || value is Boolean(_) {
      return ({ value, formula: None, keep_shared: false, }, "")
    }
  } else if ["ymd", "mdy", "dmy"].contains(kind) {
    let (value, format) = text_column_date(text, kind, date1904)
    return ({ value, formula: None, keep_shared: false, }, format)
  }
  (cell_content(text, true), "")
}

///|
fn Session::prepare_text_columns(
  self : Session,
  sheet : String,
  target : Range,
  values : Array[Array[String]],
  types : Array[String],
  formulas : Bool,
) -> (CellEditPlan, Bool) raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let updates : Map[String, CellContent] = Map([])
  let originals : Map[String, (Int, Int)] = Map([])
  let patches : Array[CellFormat] = []
  let codes : Map[String, Int] = Map([])
  for row, fields in values {
    let mut column = target.left
    for at, text in fields {
      if types[at] == "skip" {
        continue
      }
      let address : Address = { row: target.top + row, column, }
      let key = address.name()
      let (value, format) = text_column_content(
        text,
        types[at],
        formulas,
        self.date1904,
      )
      let cell = current.cells.get(key)
      let mut changed = cell.map(c => c.value).unwrap_or(Blank) != value.value ||
        cell.bind(c => c.formula) != value.formula
      if !format.is_empty() {
        let style = current.style_at(address)
        if self.styles[style].format != format {
          if !codes.contains(format) {
            codes[format] = patches.length()
            patches.push(CellFormat::new(numberFormat=Some(format)))
          }
          originals[key] = (style, codes[format])
          changed = true
        }
      }
      if changed {
        updates[key] = value
      }
      column += 1
    }
  }
  let formatting = if originals.is_empty() {
    None
  } else {
    Some(self.derive_formats(originals, patches))
  }
  let edit = self.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, formatting.map(p => p.indices).unwrap_or(Map([])))]),
    formatting~,
  )
  for key, value in updates {
    if value.formula is Some(_) &&
      edit.calculation.uncomputed.contains((index, key)) {
      @failure.reject(
        "unsupported-formula", "Text import requires supported formula calculation",
      )
    }
  }
  (edit, !updates.is_empty())
}

///|
fn Session::text_column_values(
  self : Session,
  sheet : String,
  target : Range,
  edit : CellEditPlan,
) -> Array[Array[String]] raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let candidate : Session = {
    ..self,
    sheets: edit.sheets,
    styles: edit.styles,
    parts: edit.parts,
    calculation: Some(edit.calculation),
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: target.top, column: target.left, },
    names: edit.calculation.names,
  }
  let rules = candidate.filter_rules(index, work)
  let result : Array[Array[String]] = []
  for row in target.top..<=target.bottom.min(target.top + 9) {
    let values : Array[String] = []
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let style = rules.applied(
        edit.styles[edit.sheets[index].style_at(address)],
        address,
        edit.sheets,
        index,
        edit.calculation.values,
        work,
      )
      guard style.diagnostic.is_empty() else {
        @failure.reject("protected-content", style.diagnostic)
      }
      let value = formatted(
        candidate.filter_raw(index, row, column),
        style.format,
        self.date1904,
      )
      work.spend(amount=value.length() + 1)
      values.push(value)
    }
    result.push(values)
  }
  result
}
