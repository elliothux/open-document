///|
priv struct NoteLine {
  line : Line
  advance : Double
  paragraph : Paragraph
}

///|
fn Pagination::note_lines(
  self : Pagination,
  paragraphs : Array[Paragraph],
) -> Array[NoteLine] raise @failure.Failure {
  let sources = Map::from_array(paragraphs.map(p => (p.id, p)))
  let lines : Array[NoteLine] = []
  for page_index, page in self.pages {
    for index, line in page.lines {
      guard lines.length() < 32768 else {
        @failure.reject("limit-exceeded", "Note line budget exceeded")
      }
      guard line.drawings.is_empty() && !line.caretOnly else {
        @failure.reject(
          "unsupported-layout", "Note objects require note-story layout",
        )
      }
      let leading = if lines.is_empty() { line.y } else { 0.0 }
      let advance = page.lines
        .get(index + 1)
        .map(next => next.y - line.y)
        .unwrap_or(
          if page_index == self.pages.length() - 1 {
            self.y + self.after - line.y
          } else {
            line.height
          },
        )
      lines.push({
        line: note_shift(line, -line.y + leading),
        advance: advance.max(line.height) + leading,
        paragraph: sources[line.paragraph],
      })
    }
  }
  lines
}

///|
fn reflow_notes(
  probe : TextProbe,
  flow : Flow,
  pending : Array[NoteLine],
  page : PageSetup,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> Array[NoteLine] raise @failure.Failure {
  if pending.is_empty() {
    return []
  }
  let paragraphs : Array[Paragraph] = []
  let area = Pagination::new({ ..page, top: 0, bottom: 0, height: 14400, })
  let seen : Set[Int] = Set([])
  for item in pending {
    let line = item.line
    if seen.contains(line.paragraph) {
      continue
    }
    seen.add(line.paragraph)
    let p = item.paragraph
    paragraphs.push(p)
    area.paragraph(
      cache,
      probe,
      { ..p, before: if seen.length() == 1 { line.y } else { p.before }, },
      profile,
      images,
      flow.additiveSpacing,
      startOffset=line.start,
    )
  }
  area.note_lines(paragraphs)
}
