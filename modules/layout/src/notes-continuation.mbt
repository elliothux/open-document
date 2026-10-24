///|
fn Pagination::note_lines(
  self : Pagination,
) -> Array[(Line, Double)] raise @failure.Failure {
  let lines : Array[(Line, Double)] = []
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
      lines.push(
        (
          note_shift(line, -line.y + leading),
          advance.max(line.height) + leading,
        ),
      )
    }
  }
  lines
}

///|
fn reflow_notes(
  probe : TextProbe,
  flow : Flow,
  pending : Array[(Line, Double)],
  page : PageSetup,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> Array[(Line, Double)] raise @failure.Failure {
  if pending.is_empty() {
    return []
  }
  let paragraphs : Map[Int, Paragraph] = Map([])
  for note in flow.notes {
    for p in note.content {
      paragraphs[p.id] = p
    }
  }
  let area = Pagination::new({ ..page, top: 0, bottom: 0, height: 14400, })
  let seen : Set[Int] = Set([])
  for (line, _) in pending {
    if seen.contains(line.paragraph) {
      continue
    }
    seen.add(line.paragraph)
    guard paragraphs.get(line.paragraph) is Some(p) else {
      @failure.reject("invalid-style", "Missing continued note paragraph")
    }
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
  area.note_lines()
}
