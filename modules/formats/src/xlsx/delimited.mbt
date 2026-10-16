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
/// Imports UTF-8 CSV/TSV as literal text into one new workbook with no edit history.
pub fn Session::import_delimited(
  bytes : Bytes,
  delimiter : String,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  guard bytes.length() <=
    budget.file_bytes.min(budget.retained_bytes).min(4194304) else {
    @failure.reject("limit-exceeded", "Delimited file exceeds input budget")
  }
  let source = @utf8.decode(bytes[:], ignore_bom=true) catch {
    _ => @failure.reject("invalid-delimited", "CSV/TSV requires valid UTF-8")
  }
  let rows = delimited_rows(source, delimiter)
  let xml = StringBuilder()
  let mut width = 1
  let mut xml_bytes = 0
  for r, row in rows {
    width = width.max(row.length())
    let opening = "<row r=\"\{r + 1}\">"
    xml_bytes += opening.length() + 6
    xml.write_string(opening)
    for c, text in row {
      let value = input_value(text, literal=true)
      let value = if value == Blank { Text("") } else { value }
      let (kind, content) = value_xml("", value)
      let address : Address = { row: r + 1, column: c + 1, }
      let markup = "<c r=\"\{address.name()}\"\{kind}>\{content}</c>"
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
  let blank = Session::create(budget)
  defer blank.close()
  let range : Range = { top: 1, left: 1, bottom: rows.length(), right: width, }
  let worksheet = blank.sheets[0].document
    .source()
    .replace(old="ref=\"A1\"", new="ref=\"\{range.name()}\"")
    .replace(
      old="<sheetData/>",
      new="<sheetData>\{xml.to_string()}</sheetData>",
    )
  let output = blank.opc.save(
    Map([("xl/worksheets/sheet1.xml", @utf8.encode(worksheet))]),
  )
  Session::open(output, budget)
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
