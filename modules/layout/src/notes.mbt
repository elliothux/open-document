///|
fn note_shift(line : Line, offset : Double) -> Line {
  {
    ..line.copy_geometry(),
    container: -3,
    y: line.y + offset,
    runs: line.runs.map(run => {
      ..run.copy_geometry(),
      baseline: run.baseline + offset,
    }),
    marker: line.marker.map(run => {
      ..run.copy_geometry(),
      baseline: run.baseline + offset,
    }),
    readOnlyReason: "protected-content:note-area",
  }
}

///|
fn note_references(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> Map[(Int, Int), Array[(Line, Double)]] raise @failure.Failure {
  // shortcut: Share physical-page reservations before enabling notes in columns.
  guard flow.notes.all(n => n.kind != "footnote") || flow.columns.count == 1 else {
    @failure.reject(
      "unsupported-layout", "Notes in multiple columns require shared physical-page reservations",
    )
  }
  let result : Map[(Int, Int), Array[(Line, Double)]] = Map([])
  let mut count = 0
  for note in flow.notes {
    if note.kind != "footnote" {
      continue
    }
    let area = Pagination::new({
      ..flow.page,
      top: 0,
      bottom: 0,
      height: 14400,
    })
    for paragraph in note.content {
      guard !paragraph.pageBreakBefore && !paragraph_has_break(paragraph) else {
        @failure.reject(
          "unsupported-layout", "Explicit breaks in note stories require note break handling",
        )
      }
      area.paragraph(
        cache,
        probe,
        paragraph,
        profile,
        images,
        flow.additiveSpacing,
      )
    }
    let lines = area.note_lines()
    count += lines.length()
    guard count <= 32768 else {
      @failure.reject("limit-exceeded", "Note line budget exceeded")
    }
    guard !lines.is_empty() && !result.contains((note.paragraph, note.node)) else {
      @failure.reject("invalid-style", "Missing or repeated note reference")
    }
    result[(note.paragraph, note.node)] = lines
  }
  result
}

///|
fn Flow::validate_notes(self : Flow) -> Unit raise @failure.Failure {
  guard ["sectEnd", "docEnd"].contains(self.endnotesAt) else {
    @failure.reject("invalid-style", "Invalid endnote placement")
  }
  guard self.notes.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Note count exceeds limits")
  }
  let anchors : Map[(Int, Int), String] = Map([])
  for p in self.body_field_paragraphs() {
    for s in p.spans {
      if s.field.has_prefix("NOTE:") {
        guard !anchors.contains((p.id, s.node)) else {
          @failure.reject("invalid-style", "Repeated note anchor")
        }
        anchors[(p.id, s.node)] = s.field
      }
    }
  }
  let identities : Set[String] = Set([])
  let content_ids : Set[Int] = Set([])
  for note in self.notes {
    let identity = note.kind + ":" + note.key
    guard ["footnote", "endnote"].contains(note.kind) &&
      !note.content.is_empty() &&
      !identities.contains(identity) &&
      anchors.get((note.paragraph, note.node)) == Some("NOTE:" + identity) &&
      note.content.all(p => {
        p.id < 0 &&
        p.container == -3 &&
        !p.readOnlyReason.is_empty() &&
        p.spans.all(s => s.drawing is None && s.field.is_empty())
      }) else {
      @failure.reject("invalid-style", "Invalid note story")
    }
    identities.add(identity)
    for p in note.content {
      guard !content_ids.contains(p.id) else {
        @failure.reject("invalid-style", "Repeated note paragraph identity")
      }
      guard content_ids.length() < 32768 else {
        @failure.reject("limit-exceeded", "Note paragraphs exceed line budget")
      }
      content_ids.add(p.id)
    }
  }
  guard anchors.length() == identities.length() else {
    @failure.reject("invalid-style", "Note anchors differ from note stories")
  }
}

///|
fn Pagination::fresh_notes(
  self : Pagination,
  lines : Array[Line],
) -> Array[(Int, Int)] {
  let found : Set[(Int, Int)] = Set([])
  for line in lines {
    if line.repeated {
      continue
    }
    for run in line.runs {
      for source in run.sources {
        let key = (line.paragraph, source.node)
        if self.noteReferences.contains(key) && !self.noteUsed.contains(key) {
          found.add(key)
        }
      }
    }
  }
  found.to_array()
}

///|
fn Pagination::fit_note_references(
  self : Pagination,
  lines : Array[Line],
  height : Double,
  square~ : Bool = true,
) -> Unit raise @failure.Failure {
  let fresh = self.fresh_notes(lines)
  if fresh.is_empty() {
    return
  }
  let first_line = self.noteReferences[fresh[0]][0].0
  let first = first_line.y + first_line.height
  self.fit(
    height +
    first +
    (if self.noteHeights.contains(self.pages.length() - 1) { 0.0 } else { 6.0 }),
    square~,
  )
  for key in fresh {
    self.noteUsed.add(key)
    self.notePending.append(self.noteReferences[key])
  }
  self.reserve_pending_notes(height)
}

///|
fn Pagination::reserve_pending_notes(
  self : Pagination,
  body_height : Double,
) -> Unit {
  let index = self.pages.length() - 1
  let mut height = self.noteHeights.get(index).unwrap_or(0)
  let mut available = self.page.height - self.page.bottom - self.y - body_height
  let mut added = 0.0
  while self.noteCursor < self.notePending.length() {
    let (line, advance) = self.notePending[self.noteCursor]
    let gap = if height == 0 { 6.0 } else { 0.0 }
    if available < line.y + line.height + gap {
      break
    }
    let advance = advance.min(available - gap).max(line.y + line.height)
    self.notePages
    .get_or_init(index, () => [])
    .push(note_shift(line, height + gap))
    height += gap + advance
    added += gap + advance
    available -= gap + advance
    self.noteCursor += 1
  }
  if added > 0 {
    self.noteHeights[index] = height
    self.page = { ..self.page, bottom: self.page.bottom + added, }
  }
}

///|
fn Pagination::finish_notes(
  self : Pagination,
  flow : Flow,
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
  images : Images,
  endnotes~ : Array[Note]? = None,
  flushFootnotes~ : Bool = true,
) -> Array[Array[Line]] raise @failure.Failure {
  let stories = endnotes.unwrap_or(flow.notes).filter(n => n.kind == "endnote")
  guard stories.is_empty() || self.columns.count == 1 else {
    @failure.reject(
      "unsupported-layout", "Endnote columns require shared physical-page placement",
    )
  }
  let endnotes : Map[Int, Array[Line]] = Map([])
  let mut count = self.notePending.length()
  for note in stories {
    for paragraph in note.content {
      let counts = self.pages.map(page => page.lines.length())
      self.paragraph(
        cache,
        probe,
        paragraph,
        profile,
        images,
        flow.additiveSpacing,
      )
      for index, page in self.pages {
        let start = counts.get(index).unwrap_or(0)
        count += page.lines.length() - start
        guard count <= 32768 - (self.count - (page.lines.length() - start)) else {
          @failure.reject("limit-exceeded", "Note line budget exceeded")
        }
        endnotes
        .get_or_init(index, () => [])
        .append(page.lines[start:].to_owned().map(line => note_shift(line, 0)))
        self.count -= page.lines.length() - start
        while page.lines.length() > start {
          ignore(page.lines.pop())
        }
      }
    }
  }
  self.noteBodyHeight = 0
  self.reserve_pending_notes(0)
  if flushFootnotes {
    while self.noteCursor < self.notePending.length() {
      let before = self.noteCursor
      self.next_page()
      guard self.noteCursor > before else {
        @failure.reject(
          "layout-overflow", "A footnote line exceeds the page content area",
        )
      }
    }
  }
  self.pages.mapi((index, page) => {
    let height = self.noteHeights.get(index).unwrap_or(0)
    let offset = page.height - self.sheet_setup(index).bottom - height
    let notes = self.notePages
      .get(index)
      .unwrap_or([])
      .map(line => note_shift(line, offset))
    if height > 0 {
      page.fills.push({
        x: flow.page.left,
        y: offset,
        width: if self.noteContinuations.contains(index) {
          flow.page.width - flow.page.left - flow.page.right
        } else {
          (flow.page.width - flow.page.left - flow.page.right).min(144)
        },
        height: 0.5,
        color: "000000",
      })
    }
    endnotes.get(index).unwrap_or([]) + notes
  })
}
