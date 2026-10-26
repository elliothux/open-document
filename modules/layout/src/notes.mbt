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
) -> Map[(Int, Int), Array[NoteLine]] raise @failure.Failure {
  let result : Map[(Int, Int), Array[NoteLine]] = Map([])
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
    let lines = area.note_lines(note.content)
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
  for _ in 0..<(self.columns.count + 2) {
    let prepared = fresh.map(key => {
      let lines = self.noteReferences[key]
      if self.noteReflow is Some(reflow) {
        reflow(lines, self.page)
      } else {
        lines
      }
    })
    let first = prepared[0][0].line
    let page = self.pages.length()
    self.fit(
      height +
      first.y +
      first.height +
      (if self.noteHeights.contains(page - 1) { 0.0 } else { 6.0 }),
      square~,
    )
    if page != self.pages.length() {
      continue
    }
    for index, key in fresh {
      guard self.noteCount +
        self.notePending.length() -
        self.noteCursor +
        prepared[index].length() <=
        32768 else {
        @failure.reject("limit-exceeded", "Note line budget exceeded")
      }
      self.noteUsed.add(key)
      self.notePending.append(prepared[index])
    }
    self.reserve_pending_notes(height)
    return
  }
  @failure.reject(
    "layout-overflow", "A note reference cannot fit its first line",
  )
}

///|
fn Pagination::reserve_pending_notes(
  self : Pagination,
  body_height : Double,
) -> Unit raise @failure.Failure {
  let index = self.pages.length() - 1
  let mut height = self.noteHeights.get(index).unwrap_or(0)
  let mut available = self.page.height - self.page.bottom - self.y - body_height
  let mut added = 0.0
  while self.noteCursor < self.notePending.length() {
    let item = self.notePending[self.noteCursor]
    let line = item.line
    let advance = item.advance
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
    self.noteCount += 1
    guard self.noteCount <= 32768 - self.count else {
      @failure.reject("limit-exceeded", "Note line budget exceeded")
    }
  }
  if added > 0 {
    self.noteHeights[index] = height
    self.page = { ..self.page, bottom: self.page.bottom + added, }
  }
}

///|
fn Pagination::flush_footnotes(
  self : Pagination,
  flush : Bool,
) -> Unit raise @failure.Failure {
  self.noteBodyHeight = 0
  self.reserve_pending_notes(0)
  if flush || self.columns.count > 1 {
    while self.noteCursor < self.notePending.length() &&
          (flush || self.pages.length() % self.columns.count != 0) {
      let before = self.noteCount
      self.next_page()
      guard self.noteCount > before else {
        @failure.reject(
          "layout-overflow", "A footnote line exceeds the page content area",
        )
      }
    }
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
  let endnotes : Map[Int, Array[Line]] = Map([])
  let counts = self.pages.map(page => page.lines.length())
  guard self.noteCount + self.notePending.length() - self.noteCursor <=
    32768 - self.count else {
    @failure.reject("limit-exceeded", "Note line budget exceeded")
  }
  for note in stories {
    for paragraph in note.content {
      self.paragraph(
        cache,
        probe,
        paragraph,
        profile,
        images,
        flow.additiveSpacing,
      )
    }
  }
  let mut end_count = 0
  for index, page in self.pages {
    let start = counts.get(index).unwrap_or(0)
    end_count += page.lines.length() - start
    endnotes[index] = page.lines[start:]
      .to_owned()
      .map(line => note_shift(line, 0))
    self.count -= page.lines.length() - start
    while page.lines.length() > start {
      ignore(page.lines.pop())
    }
  }
  self.flush_footnotes(flushFootnotes)
  guard end_count + self.noteCount + self.notePending.length() - self.noteCursor <=
    32768 - self.count else {
    @failure.reject("limit-exceeded", "Note line budget exceeded")
  }
  self.pages.mapi((index, page) => {
    let height = self.noteHeights.get(index).unwrap_or(0)
    let setup = self.page_at(index)
    let offset = page.height -
      self.sheet_setup(index / self.columns.count).bottom -
      height
    let notes = self.notePages
      .get(index)
      .unwrap_or([])
      .map(line => note_shift(line, offset))
    if height > 0 {
      page.fills.push({
        x: setup.left,
        y: offset,
        width: if self.noteContinuations.contains(index) {
          setup.width - setup.left - setup.right
        } else {
          (setup.width - setup.left - setup.right).min(144)
        },
        height: 0.5,
        color: "000000",
      })
    }
    endnotes.get(index).unwrap_or([]) + notes
  })
}
