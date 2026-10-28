///|
fn markdown_text(text : String) -> String {
  let output = StringBuilder()
  for c in text {
    if "\\`*_{}[]<>()#+-.!|".contains(c.to_string()) {
      output.write_string("\\")
    }
    output.write_char(c)
  }
  output.to_string()
}

///|
/// Export reconstructed reading blocks at one committed revision. Source markup
/// is escaped; images contain only freshly encoded PNG pixels and links use the
/// navigation allowlist. Ambiguous layout and omitted content are reported.
pub fn PdfSession::export_text(
  self : PdfSession,
  revision : Int32,
  ids : Array[String],
  format : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded? : @layout.Images,
) -> (Bytes, Array[String]) raise @failure.Failure {
  self.check(revision)
  guard ["html", "markdown"].contains(format) &&
    !ids.is_empty() &&
    ids.length() <= self.budget.pages else {
    @failure.reject(
      "invalid-operation", "Choose bounded PDF pages and a text export format",
    )
  }
  pdf_bound(self.budget, () => {
    let output = StringBuilder()
    if format == "html" {
      output.write_string(
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\"><title>PDF structured export</title></head><body>",
      )
    }
    let warnings : Array[String] = []
    let seen : Map[String, Bool] = Map([])
    let mut units = 0
    let families : Map[String, String] = Map([])
    for index, info in supplied.font_info() {
      families[info.identity] = supplied.font_family(index)
    }
    for index, id in ids {
      guard !seen.contains(id) else {
        @failure.reject("invalid-page", "Duplicate PDF output page")
      }
      seen[id] = true
      let display = self.extract_page(revision, id, supplied, profile, decoded?)
      defer display.close()
      guard display.textComplete else {
        @failure.reject(
          "protected-content", "Text export requires complete Unicode mapping on every selected page",
        )
      }
      guard display.text.length() <= 1048576 - units else {
        @failure.reject("limit-exceeded", "PDF text export exceeds budget")
      }
      units += display.text.length()
      read_warning(
        warnings,
        "Page \{index + 1}: reading order and paragraph boundaries are inferred; exact page layout and interactive behavior are not retained",
      )
      if !display.displayComplete {
        warnings.push("Page \{index + 1}: page drawing is incomplete")
      }
      let lines = read_text_lines(display, families, warnings, index + 1)
      let tables = read_tables(display.paths, lines)
      for pathIndex in 0..<display.paths.length() {
        if !tables.any(table => table.paths.contains(pathIndex)) {
          read_warning(
            warnings,
            "Page \{index + 1}: non-table vector artwork is omitted",
          )
          break
        }
      }
      let links = self.output_links(id, ids, warnings, index + 1)
      let blocks = output_blocks(
        display,
        lines,
        tables,
        links,
        warnings,
        index + 1,
        self.budget.outputBytes,
      )
      if format == "html" {
        output <+
          "<article id=\"pdf-page-\{index + 1}\" data-page=\"\{index + 1}\">"
        for block in blocks {
          output.write_string(block.html)
          output.write_string("\n")
        }
        output.write_string("</article>\n")
      } else {
        if index > 0 {
          output.write_string("\n\n---\n\n")
        }
        output <+ "<a id=\"pdf-page-\{index + 1}\"></a>\n\n"
        for block in blocks {
          output.write_string(block.markdown)
          output.write_string("\n\n")
        }
      }
      guard output.to_string().length() <= self.budget.outputBytes else {
        @failure.reject(
          "limit-exceeded", "PDF structured output exceeds budget",
        )
      }
    }
    if format == "html" {
      output.write_string("</body></html>")
    }
    let bytes = @utf8.encode(output.to_string())
    guard bytes.length() <= self.budget.outputBytes else {
      @failure.reject("limit-exceeded", "PDF text output exceeds budget")
    }
    (bytes, warnings)
  })
}
