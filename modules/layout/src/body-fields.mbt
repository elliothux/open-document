///|
fn Flow::body_fields(
  self : Flow,
) -> Map[(Int, Int), String] raise @failure.Failure {
  guard self.bookmarks.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Field targets exceed limits")
  }
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
        if span.field.has_prefix("PAGEREF:") {
          ignore(PageReference::parse(span.field))
        }
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
  values : Map[(Int, Int), String],
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
        let text = values
          .get((paragraph.id, span.node))
          .unwrap_or_else(() => {
            if span.field.has_prefix("PAGEREF:") {
              let reference = PageReference::parse(span.field)
              if !self.bookmarks.contains(reference.bookmark.to_lower()) {
                "Error! Bookmark not defined."
              } else if reference.relative {
                "below"
              } else {
                self.pageNumbering.field_text(reference.page_code(), 0, total)
              }
            } else {
              self.pageNumbering.field_text(span.field, 0, total)
            }
          })
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
