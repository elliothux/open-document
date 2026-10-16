///|
fn parse_tsv(source : String) -> Array[Array[String]] raise @failure.Failure {
  guard source.length() <= 1048576 && @xml.valid_text(source) else {
    @failure.reject(
      "limit-exceeded", "Clipboard text is invalid or exceeds budget",
    )
  }
  let source = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  let mut quoted = false
  let mut closed = false
  let mut at_start = true
  let mut count = 0
  let mut i = 0
  while i < source.length() {
    let ch = source.get_char(i).unwrap()
    i += ch.to_string().length()
    if quoted {
      if ch == '"' {
        if i < source.length() && source[i] == 34 {
          field.write_char('"')
          i += 1
        } else {
          quoted = false
          closed = true
        }
      } else {
        field.write_char(ch)
      }
    } else if ch == '\t' || ch == '\n' {
      row.push(field.to_string())
      count += 1
      field = StringBuilder()
      at_start = true
      closed = false
      if ch == '\n' {
        rows.push(row)
        row = []
      }
    } else if ch == '"' && at_start {
      quoted = true
      at_start = false
    } else {
      guard !closed else {
        @failure.reject(
          "invalid-clipboard", "Unexpected text after quoted field",
        )
      }
      field.write_char(ch)
      at_start = false
    }
    guard count + row.length() <= 8192 && rows.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Clipboard cells exceed budget")
    }
  }
  guard !quoted else {
    @failure.reject("invalid-clipboard", "Unclosed quoted field")
  }
  if !source.has_suffix("\n") || !row.is_empty() || rows.is_empty() {
    row.push(field.to_string())
    rows.push(row)
  }
  let width = rows[0].length()
  guard width > 0 && rows.length().to_int64() * width.to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Clipboard rectangle exceeds budget")
  }
  guard rows.all(row => row.length() == width) else {
    @failure.reject("invalid-clipboard", "Clipboard rows must have equal width")
  }
  rows
}

///|
pub fn Session::paste(
  self : Session,
  revision : Int,
  text : String,
  accept_warnings~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let rows = parse_tsv(text)
  let target : Range = {
    top: self.selection.1.top,
    left: self.selection.1.left,
    bottom: self.selection.1.top + rows.length() - 1,
    right: self.selection.1.left + rows[0].length() - 1,
  }
  guard target.bottom <= 1048576 && target.right <= 16384 else {
    @failure.reject(
      "invalid-address", "Clipboard rectangle exceeds worksheet bounds",
    )
  }
  let values = rows.map(row => {
    row.map(text => {
      if text.has_prefix("=") || text.has_prefix("'") {
        "'" + text
      } else {
        text
      }
    })
  })
  self.replace(
    revision,
    self.selection.0,
    target.name(),
    values,
    accept_warnings~,
  )
}

///|
fn Session::clear_contents(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let range = self.selection.1
  let height = range.bottom - range.top + 1
  let width = range.right - range.left + 1
  guard height.to_int64() * width.to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Clear rectangle exceeds budget")
  }
  self.replace(
    revision,
    self.selection.0,
    range.name(),
    Array::makei(height, _ => Array::make(width, "")),
  )
}

///|
pub fn Session::copy(
  self : Session,
  revision : Int,
) -> String raise @failure.Failure {
  self.check_revision(revision)
  let range = self.selection.1
  guard (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096L else {
    @failure.reject("limit-exceeded", "Copy rectangle exceeds budget")
  }
  let index = self.sheet_index(self.selection.0)
  let sheet = self.sheets[index]
  let lines : Array[String] = []
  let mut units = 0
  for row in range.top..<=range.bottom {
    let fields : Array[String] = []
    for column in range.left..<=range.right {
      let address : Address = { row, column, }
      let merge = sheet.cell_range(address)
      let text = if merge.top != row || merge.left != column {
        ""
      } else {
        let key = address.name()
        let cell = sheet.cells.get(key)
        let value = self.calculation
          .bind(calculation => calculation.values.get((index, key)))
          .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
        if cell.bind(cell => cell.formula) is Some(_) && value == Blank {
          "Not calculated"
        } else {
          formatted(
            value,
            self.styles[sheet.style_at(address)].format,
            self.date1904,
          )
        }
      }
      let text = if text.contains("\t") ||
        text.contains("\n") ||
        text.contains("\r") ||
        text.contains("\"") {
        "\"" + text.replace_all(old="\"", new="\"\"") + "\""
      } else {
        text
      }
      units += text.length() + 1
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Copied text exceeds budget")
      }
      fields.push(text)
    }
    lines.push(fields.join("\t"))
  }
  lines.join("\n")
}
