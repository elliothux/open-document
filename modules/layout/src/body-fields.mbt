///|
fn Flow::body_fields(
  self : Flow,
) -> Map[(Int, Int), String] raise @failure.Failure {
  guard self.bookmarks.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Field targets exceed limits")
  }
  let fields : Map[(Int, Int), String] = Map([])
  for paragraph in self.body_field_paragraphs() {
    for span in paragraph.spans {
      if !span.field.is_empty() {
        if span.field.has_prefix("PAGEREF:") {
          ignore(PageReference::parse(span.field))
        } else if span.field.has_prefix("REF:") {
          ignore(TextReference::parse(span.field))
        } else if span.field.has_prefix("SEQ:") {
          ignore(SequenceField::parse(span.field))
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
            } else if span.field.has_prefix("REF:") {
              span.text
            } else if span.field.has_prefix("SEQ:") {
              SequenceField::parse(span.field).text(1)
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

///|
fn Flow::body_field_paragraphs(
  self : Flow,
) -> Array[Paragraph] raise @failure.Failure {
  let paragraphs : Array[Paragraph] = []
  let mut table = 0
  for index in 0..<=self.paragraphs.length() {
    while table < self.tables.length() &&
          self.tables[table].beforeParagraph == index {
      for row in self.tables[table].rows {
        for cell in row {
          paragraphs.append(cell)
        }
      }
      table += 1
    }
    if index < self.paragraphs.length() {
      paragraphs.push(self.paragraphs[index])
    }
  }
  guard table == self.tables.length() else {
    @failure.reject("unsupported-layout", "Invalid body field table order")
  }
  paragraphs
}
