///|
/// Refreshes body PAGE/NUMPAGES cached results in one exact source transaction.
pub fn Session::update_body_page_fields(
  self : Session,
  revision : Int,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  ignore(self.editable_page_section(tree))
  let flow = self.flow()
  let layout = @layout.paginate(probe, flow, profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Body field update requires a complete layout",
    )
  }
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  let fields : Map[(Int, Int), Bool] = Map([])
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if !span.field.is_empty() {
        fields[(paragraph.id, span.node)] = true
      }
    }
  }
  let pages : Map[(Int, Int), Int] = Map([])
  for page, frame in layout.pages {
    for line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          let key = (line.paragraph, source.node)
          if fields.contains(key) && !pages.contains(key) {
            pages[key] = page
          }
        }
      }
    }
  }
  let affected : Array[Int] = []
  let changes : Array[@xml.SourceChange] = []
  let mut count = 0
  for paragraph in paragraphs {
    for id, code in tree.running_fields(paragraph.id) {
      count += 1
      guard count <= 4096 else {
        @failure.reject("limit-exceeded", "Body page fields exceed limits")
      }
      let value = if code.is_empty() {
        ""
      } else {
        guard pages.get((paragraph.id, id)) is Some(page) else {
          @failure.reject(
            "unsupported-layout", "Body field position is unavailable",
          )
        }
        flow.pageNumbering.field_text(code, page, layout.pages.length())
      }
      let node = tree.nodes[id]
      if node.text == value {
        continue
      }
      let source = original.source()[node.start:node.end]
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Opaque field result source cannot be refreshed",
        )
      }
      let text = @xml.escape_text(value)
      changes.push(
        if node.empty {
          {
            node: id,
            offset: node.opening_end - node.start - 2,
            length: 2,
            xml: ">\{text}</\{node.qualified}>",
          }
        } else {
          {
            node: id,
            offset: node.opening_end - node.start,
            length: node.closing_start - node.opening_end,
            xml: text,
          }
        },
      )
      if !affected.contains(paragraph.id) {
        affected.push(paragraph.id)
      }
    }
  }
  if changes.is_empty() {
    return self.edit_state()
  }
  let (candidate, step) = original.edit_source(changes)
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [step],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs: affected,
      bytes: edit_bytes(step),
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
