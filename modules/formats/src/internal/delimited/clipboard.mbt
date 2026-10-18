///|
pub fn quote_field(text : String) -> String {
  if text.contains("\t") ||
    text.contains("\n") ||
    text.contains("\r") ||
    text.contains("\"") {
    "\"" + text.replace_all(old="\"", new="\"\"") + "\""
  } else {
    text
  }
}

///|
/// Parses a bounded rectangular clipboard matrix with quoted fields.
pub fn parse_tsv(
  source : String,
) -> Array[Array[String]] raise @failure.Failure {
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
