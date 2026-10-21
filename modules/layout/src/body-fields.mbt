///|
fn Flow::body_fields(
  self : Flow,
) -> Map[(Int, Int), String] raise @failure.Failure {
  let fields : Map[(Int, Int), String] = Map([])
  let paragraphs = self.paragraphs.copy()
  for table in self.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if !span.field.is_empty() {
        guard span.drawing is None && fields.length() < 4096 else {
          @failure.reject("limit-exceeded", "Body page fields exceed limits")
        }
        fields[(paragraph.id, span.node)] = span.field
      }
    }
  }
  fields
}

///|
fn Flow::resolve_body_fields(
  self : Flow,
  pages : Map[(Int, Int), Int],
  total : Int,
) -> (Flow, Bool) raise @failure.Failure {
  let mut stable = true
  let resolve = fn(paragraph : Paragraph) raise @failure.Failure {
    {
      ..paragraph,
      spans: paragraph.spans.map(span => {
        if span.field.is_empty() {
          return span
        }
        let text = self.pageNumbering.field_text(
          span.field,
          pages.get((paragraph.id, span.node)).unwrap_or(0),
          total,
        )
        if text != span.text {
          stable = false
        }
        { ..span, text, }
      }),
    }
  }
  let paragraphs = self.paragraphs.map(resolve)
  let tables = self.tables.map(table => {
    ..table,
    rows: table.rows.map(row => row.map(cell => cell.map(resolve))),
  })
  ({ ..self, paragraphs, tables, }, stable)
}

///|
fn Pagination::body_field_pages(
  self : Pagination,
  fields : Map[(Int, Int), String],
) -> (Map[(Int, Int), Int], Array[String]) {
  let pages : Map[(Int, Int), Int] = Map([])
  let diagnostics : Array[String] = []
  if fields.is_empty() {
    return (pages, diagnostics)
  }
  for page, frame in self.pages {
    for line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          let key = (line.paragraph, source.node)
          if fields.get(key) is Some(code) {
            if !pages.contains(key) {
              pages[key] = page
            }
            if line.repeated &&
              (code == "PAGE" || code.has_prefix("PAGE:")) &&
              !diagnostics.contains(
                "unsupported-layout:repeated-body-page-field",
              ) {
              diagnostics.push("unsupported-layout:repeated-body-page-field")
            }
          }
        }
      }
    }
  }
  if pages.length() != fields.length() {
    diagnostics.push("unsupported-layout:body-field-position-unavailable")
  }
  (pages, diagnostics)
}
