///|
fn Flow::body_fields(
  self : Flow,
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  guard self.bookmarks.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Field targets exceed limits")
  }
  let fields : Map[(Int32, Int32), String] = Map([])
  let mut ordinary = 0
  let page_notes = Map::from_array(
    self.notes
    .filter(note => note.numbering.restart == "eachPage")
    .map(note => ((note.paragraph, note.node), true)),
  )
  for paragraph in self.body_field_paragraphs() {
    for span in paragraph.spans {
      if !span.field.is_empty() &&
        (
          !span.field.has_prefix("NOTE:") ||
          page_notes.contains((paragraph.id, span.node))
        ) {
        if span.field.has_prefix("PAGEREF:") {
          ignore(PageReference::parse(span.field))
        } else if span.field.has_prefix("REF:") {
          ignore(TextReference::parse(span.field))
        } else if span.field.has_prefix("NOTEREF:") {
          ignore(NoteReference::parse(span.field))
        } else if span.field.has_prefix("SEQ:") {
          ignore(SequenceField::parse(span.field))
        } else if span.field.has_prefix("STYLEREF:") {
          ignore(style_reference_level(span.field))
        }
        if !span.field.has_prefix("NOTE:") &&
          !fields.contains((paragraph.id, span.node)) {
          ordinary += 1
        }
        guard span.drawing is None &&
          ordinary <= 4096 &&
          fields.length() < 12288 else {
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
  values : Map[(Int32, Int32), String],
  total : Int32,
) -> (Flow, Bool) raise @failure.Failure {
  let mut stable = true
  let resolve = fn(paragraph : Paragraph) raise @failure.Failure {
    {
      ..paragraph,
      spans: paragraph.spans.map(span => {
        if span.field.is_empty() ||
          (
            span.field.has_prefix("NOTE:") &&
            !values.contains((paragraph.id, span.node))
          ) {
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
            } else if span.field.has_prefix("NOTE:") ||
              span.field.has_prefix("REF:") ||
              span.field.has_prefix("NOTEREF:") ||
              span.field.has_prefix("STYLEREF:") ||
              span.field.has_prefix("CITATION:") {
              span.text
            } else if span.field.has_prefix("SEQ:") {
              SequenceField::parse(span.field).text(1L)
            } else {
              self.pageNumbering.field_text(span.field, 0, total)
            }
          })
        if text != span.text {
          stable = false
        }
        let style = if span.field.has_prefix("NOTEREF:") {
          let reference = NoteReference::parse(span.field)
          if reference.superscript &&
            !reference.relative &&
            text != "Error! Bookmark not defined." {
            { ..span.style, script: "superscript", }
          } else {
            span.style
          }
        } else {
          span.style
        }
        { ..span, text, style, }
      }),
    }
  }
  let paragraphs = self.paragraphs.map(resolve)
  let tables = self.tables.map(table => table.map_paragraphs(resolve))
  let notes = self.notes.map(note => {
    guard values.get((note.paragraph, note.node)) is Some(label) else {
      return note
    }
    {
      ..note,
      content: note.content.map(paragraph => {
        ..paragraph,
        spans: paragraph.spans.map(span => {
          if span.node == note.numbering.marker && span.text != label {
            stable = false
            { ..span, text: label, }
          } else {
            span
          }
        }),
      }),
    }
  })
  ({ ..self, paragraphs, tables, notes, }, stable)
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
      paragraphs.append(self.tables[table].paragraphs())
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
