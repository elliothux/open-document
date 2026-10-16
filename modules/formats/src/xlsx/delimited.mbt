///|
fn delimited_rows(
  source : String,
  delimiter : String,
) -> Array[Array[String]] raise @failure.Failure {
  guard [",", "\t"].contains(delimiter) else {
    @failure.reject("invalid-operation", "Delimiter must be a comma or tab")
  }
  guard source.length() <= 1048576 && @xml.valid_text(source) else {
    @failure.reject(
      "limit-exceeded", "Delimited input exceeds text limits or contains invalid XML characters",
    )
  }
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  let mut quoted = false
  let mut closed = false
  let mut start = true
  let mut cells = 0
  let mut index = 0
  let mut ended = false
  while index < source.length() {
    let ch = source.get_char(index).unwrap()
    index += ch.to_string().length()
    ended = false
    if quoted {
      if ch == '"' {
        if index < source.length() && source[index] == 34 {
          field.write_char('"')
          index += 1
        } else {
          quoted = false
          closed = true
        }
      } else {
        field.write_char(ch)
      }
    } else if ch.to_string() == delimiter || ch == '\r' || ch == '\n' {
      row.push(field.to_string())
      cells += 1
      field = StringBuilder()
      closed = false
      start = true
      if ch == '\r' || ch == '\n' {
        if ch == '\r' && index < source.length() && source[index] == 10 {
          index += 1
        }
        rows.push(row)
        row = []
        ended = true
      }
    } else if ch == '"' && start {
      quoted = true
      start = false
    } else {
      guard !closed && ch != '"' else {
        @failure.reject(
          "invalid-delimited", "Unexpected text or quote outside a quoted field",
        )
      }
      field.write_char(ch)
      start = false
    }
    guard cells <= 65536 && row.length() <= 16384 && rows.length() <= 65536 else {
      @failure.reject("limit-exceeded", "Delimited rows or cells exceed limits")
    }
  }
  guard !quoted else {
    @failure.reject("invalid-delimited", "Unclosed quoted field")
  }
  if !ended || rows.is_empty() {
    row.push(field.to_string())
    rows.push(row)
    cells += 1
  }
  guard cells <= 65536 && rows.all(row => row.length() <= 16384) else {
    @failure.reject("limit-exceeded", "Delimited cells exceed limits")
  }
  rows
}

///|
/// Imports UTF-8 CSV/TSV with opt-in conversions into one new workbook with no edit history.
pub fn Session::import_delimited(
  bytes : Bytes,
  delimiter : String,
  budget : @archive.Budget,
  numbers~ : Bool = false,
  dates~ : Bool = false,
  formulas~ : Bool = false,
) -> Session raise @failure.Failure {
  guard bytes.length() <=
    budget.file_bytes.min(budget.retained_bytes).min(4194304) else {
    @failure.reject("limit-exceeded", "Delimited file exceeds input budget")
  }
  let source = @utf8.decode(bytes[:], ignore_bom=true) catch {
    _ => @failure.reject("invalid-delimited", "CSV/TSV requires valid UTF-8")
  }
  let rows = delimited_rows(source, delimiter)
  let formats : Map[String, (Int, Int)] = Map([])
  let codes = ["yyyy-mm-dd", "hh:mm:ss", "m/d/yy h:mm"]
  let converted = rows.map(row => {
    row.map(text => {
      let literal = input_value(text, literal=true)
      if formulas && text.has_prefix("=") {
        (cell_content(text, false), "")
      } else {
        let date = if dates { formula_date_text(text, false) } else { Blank }
        let (value, code) = if date is Number(_) {
          let index = if !text.contains(":") {
            0
          } else if text.contains("-") || text.contains("/") {
            2
          } else {
            1
          }
          let code = codes[index]
          formats[code] = (0, index)
          (date, code)
        } else if numbers && input_value(text, literal=false) is Number(value) {
          (Number(value), "")
        } else {
          (if literal == Blank { Text("") } else { literal }, "")
        }
        ({ value, formula: None, keep_shared: false, }, code)
      }
    })
  })
  let blank = Session::create(budget)
  defer blank.close()
  let replacements : Map[String, Bytes] = Map([])
  let indices : Map[String, Int] = Map([])
  if !formats.is_empty() {
    let styles = blank.derive_formats(
      formats,
      codes.map(code => CellFormat::new(numberFormat=Some(code))),
    )
    for code, index in styles.indices {
      indices[code] = index
    }
    for path, document in styles.parts {
      replacements[path] = document.bytes()
    }
  }
  let xml = StringBuilder()
  let mut width = 1
  let mut xml_bytes = 0
  for r, row in converted {
    width = width.max(row.length())
    let opening = "<row r=\"\{r + 1}\">"
    xml_bytes += opening.length() + 6
    xml.write_string(opening)
    for c, (cell, code) in row {
      let (kind, content) = content_xml("", cell)
      let style = if code == "" { "" } else { " s=\"\{indices[code]}\"" }
      let address : Address = { row: r + 1, column: c + 1, }
      let markup = "<c r=\"\{address.name()}\"\{style}\{kind}>\{content}</c>"
      xml_bytes += @utf8.encode(markup).length()
      xml.write_string(markup)
    }
    xml.write_string("</row>")
    guard xml_bytes <= budget.entry_bytes else {
      @failure.reject(
        "limit-exceeded", "Imported worksheet exceeds entry budget",
      )
    }
  }
  let range : Range = { top: 1, left: 1, bottom: rows.length(), right: width, }
  let worksheet = blank.sheets[0].document
    .source()
    .replace(old="ref=\"A1\"", new="ref=\"\{range.name()}\"")
    .replace(
      old="<sheetData/>",
      new="<sheetData>\{xml.to_string()}</sheetData>",
    )
  replacements["xl/worksheets/sheet1.xml"] = @utf8.encode(worksheet)
  let session = Session::open(blank.opc.save(replacements), budget)
  errdefer session.close()
  guard session.read_only == "" else {
    @failure.reject("invalid-delimited", session.read_only)
  }
  if formulas && session.calculation is Some(calculation) {
    ignore(session.cache_edits(session.sheets, calculation))
    session.validate(session.sheets)
  }
  session
}

///|
/// Exports logical values with CRLF and quotes; dangerous text prefixes gain a literal apostrophe.
pub fn Session::export_csv(
  self : Session,
  revision : Int,
  selection~ : Bool = false,
) -> Bytes raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(self.selection.0)
  let sheet = self.sheets[index]
  let used = sheet.used()
  let range = if selection {
    self.selection.1
  } else {
    { ..used, top: 1, left: 1, }
  }
  guard (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    65536 else {
    @failure.reject("limit-exceeded", "CSV rectangle exceeds 65536 cells")
  }
  let output = StringBuilder()
  let mut units = 0
  for row in range.top..<=range.bottom {
    let fields : Array[String] = []
    for column in range.left..<=range.right {
      let address : Address = { row, column, }
      let merge = sheet.cell_range(address)
      let cell = sheet.cells.get(address.name())
      let value = if merge.top != row || merge.left != column {
        Blank
      } else {
        self.calculation
        .bind(calc => calc.values.get((index, address.name())))
        .unwrap_or(cell.map(c => c.value).unwrap_or(Blank))
      }
      guard cell.bind(c => c.formula) is None || value != Blank else {
        @failure.reject(
          "uncalculated-formula", "CSV requires a calculated value or imported cache",
        )
      }
      let text = value.display()
      guard @xml.valid_text(text) else {
        @failure.reject(
          "invalid-delimited", "CSV cannot represent unsupported control characters",
        )
      }
      let text = if (
          value is Text(_) &&
          ["=", "+", "-", "@"].any(prefix => text.trim().has_prefix(prefix))
        ) ||
        (
          value is Text(_) &&
          (
            text.has_prefix("\t") ||
            text.has_prefix("\r") ||
            text.has_prefix("\n")
          )
        ) {
        "'" + text
      } else {
        text
      }
      let text = if [",", "\"", "\r", "\n"].any(c => text.contains(c)) {
        "\"" + text.replace_all(old="\"", new="\"\"") + "\""
      } else {
        text
      }
      units += text.length() + 1
      guard units <= 4194304 else {
        @failure.reject("limit-exceeded", "CSV output exceeds text budget")
      }
      fields.push(text)
    }
    output.write_string(fields.join(",") + "\r\n")
  }
  let bytes = @utf8.encode(output.to_string())
  guard bytes.length() <= self.budget.output_bytes else {
    @failure.reject("limit-exceeded", "CSV output exceeds byte budget")
  }
  bytes
}
