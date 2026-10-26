///|
/// Page properties take effect after the preceding body paragraph and table counts.
pub(all) struct SectionBreak {
  beforeParagraph : Int
  beforeTable : Int
  kind : String
  restartNumbering : Bool
  page : PageSetup
  pageBorders : PageBorders
  pageNumbering : PageNumbering
  columns : Columns
  headers : Map[String, Array[Paragraph]]
  headerDistance : Double
  footers : Map[String, Array[Paragraph]]
  footerDistance : Double
  differentFirst : Bool
  differentEven : Bool
} derive(ToJson)

///|
pub extend SectionBreak with ToJson::{to_json}

///|
fn Flow::section_body(
  self : Flow,
  index : Int,
  numbering : PageNumbering,
) -> Flow {
  let previous = self.sectionBreaks.get(index - 1)
  let next = self.sectionBreaks.get(index)
  let start = previous.map(s => s.beforeParagraph).unwrap_or(0)
  let table_start = previous.map(s => s.beforeTable).unwrap_or(0)
  let body = {
    ..self,
    sectionBreaks: [],
    pageNumbering: numbering,
    paragraphs: self.paragraphs[start:next
    .map(s => s.beforeParagraph)
    .unwrap_or(self.paragraphs.length())].to_owned(),
    tables: self.tables[table_start:next
    .map(s => s.beforeTable)
    .unwrap_or(self.tables.length())]
    .to_owned()
    .map(table => { ..table, beforeParagraph: table.beforeParagraph - start, }),
  }
  let part = match previous {
    None => body
    Some(section) =>
      {
        ..body,
        page: section.page,
        pageBorders: section.pageBorders,
        columns: section.columns,
        headers: section.headers,
        headerDistance: section.headerDistance,
        footers: section.footers,
        footerDistance: section.footerDistance,
        differentFirst: section.differentFirst,
        differentEven: section.differentEven,
      }
  }
  let ids : Set[Int] = Set([])
  for p in part.paragraphs {
    ids.add(p.id)
  }
  for table in part.tables {
    for row in table.rows {
      for cell in row {
        for p in cell {
          ids.add(p.id)
        }
      }
    }
  }
  { ..part, notes: self.notes.filter(n => ids.contains(n.paragraph)), }
}

///|
fn Flow::validate_sections(self : Flow) -> Unit raise @failure.Failure {
  guard self.sectionBreaks.length() < 1024 else {
    @failure.reject("limit-exceeded", "Section count exceeds page budget")
  }
  for section in self.sectionBreaks; paragraph = 0, table = 0 {
    guard section.beforeParagraph > paragraph &&
      section.beforeParagraph <= self.paragraphs.length() &&
      section.beforeTable >= table &&
      section.beforeTable <= self.tables.length() &&
      self.tables
      .get(section.beforeTable - 1)
      .map(t => t.beforeParagraph < section.beforeParagraph)
      .unwrap_or(true) &&
      self.tables
      .get(section.beforeTable)
      .map(t => t.beforeParagraph >= section.beforeParagraph)
      .unwrap_or(true) else {
      @failure.reject(
        "invalid-section", "Section boundary does not follow a body paragraph",
      )
    }
    guard ["nextPage", "oddPage", "evenPage", "continuous"].contains(
      section.kind,
    ) else {
      @failure.reject("unsupported-layout", "Unsupported section break type")
    }
    section.page.validate()
    section.pageBorders.validate()
    section.pageNumbering.validate()
    ignore(section.columns.width(section.page))
    continue section.beforeParagraph, section.beforeTable
  }
}

///|
fn paginate_sections(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> (
  Array[PageFrame],
  Array[Array[Line]],
  Array[String],
  Array[PageNumbering],
  Array[(Int, Int)?],
) raise @failure.Failure {
  let fields = flow.body_fields()
  let fixed = flow.fixed_body_field_values(fields)
  let mut body = flow.resolve_body_fields(fixed, 1).0
  let mut total = 1
  for attempt in 0..<8 {
    let combined = Pagination::new(flow.page)
    combined.pages.clear()
    let running : Array[Array[Line]] = []
    let contexts : Array[(PageNumbering, Int)] = []
    let diagnostics : Array[String] = []
    let section_numbering : Array[PageNumbering] = []
    let page_sections : Array[(Int, Int)?] = []
    let mut numbering = flow.pageNumbering
    let mut lines = 0
    let mut pending : Array[NoteLine] = []
    let mut continuation : SectionContinuation? = None
    for index in 0..<=flow.sectionBreaks.length() {
      let shared = flow.sectionBreaks
        .get(index - 1)
        .bind(section => {
          if section.kind == "continuous" {
            continuation.filter(state => {
              state.page.width == section.page.width &&
              state.page.height == section.page.height
            })
          } else {
            None
          }
        })
      let next_number = numbering
      if flow.sectionBreaks.get(index - 1) is Some(section) {
        let parity = match section.kind {
          "oddPage" => 1L
          "evenPage" => 0L
          _ => -1L
        }
        let start = if section.restartNumbering {
          section.pageNumbering.start
        } else {
          numbering.start
        }
        if parity >= 0 && start % 2L != parity {
          let previous = combined.pages.last().unwrap()
          combined.pages.push({
            ..previous,
            lines: [],
            borders: [],
            fills: [],
            pageBorders: [],
            cellAreas: [],
          })
          running.push([])
          page_sections.push(None)
          contexts.push((numbering, 0))
          numbering = { ..numbering, start: numbering.start + 1L, }
        }
        numbering = {
          ..section.pageNumbering,
          start: if section.restartNumbering {
            start + (if parity >= 0 && start % 2L != parity { 1L } else { 0L })
          } else {
            numbering.start - (if shared is Some(_) { 1L } else { 0L })
          },
        }
      }
      numbering.validate()
      let mut part = body.section_body(index, numbering)
      let endnotes = if flow.endnotesAt == "docEnd" {
        if index == flow.sectionBreaks.length() {
          flow.notes.filter(n => n.kind == "endnote")
        } else {
          []
        }
      } else {
        part.notes.filter(n => n.kind == "endnote")
      }
      pending = reflow_notes(
        probe,
        flow,
        pending,
        part.page,
        cache,
        profile,
        images,
      )
      let (first, first_stories, _, _, _, first_problems) = paginate_running(
        probe,
        part,
        cache,
        profile,
        images,
        documentTotal=Some(total),
        pendingNotes=pending,
        endnotes=Some(endnotes),
        flushFootnotes=index == flow.sectionBreaks.length(),
        resolveBodyFields=false,
        continuation=shared,
      )
      let joined = shared
        .map(state => {
          first.pages[0].lines.length() > state.frame.lines.length() ||
          first.pages[0].cellAreas.length() > state.frame.cellAreas.length() ||
          first_stories[0].any(line => line.container == -3) ||
          (part.paragraphs.is_empty() && part.tables.is_empty())
        })
        .unwrap_or(false)
      let (pagination, stories, problems) = if shared is Some(_) && !joined {
        let section = flow.sectionBreaks[index - 1]
        numbering = {
          ..numbering,
          start: if section.restartNumbering {
            section.pageNumbering.start
          } else {
            next_number.start
          },
        }
        part = body.section_body(index, numbering)
        let (pagination, stories, _, _, _, problems) = paginate_running(
          probe,
          part,
          cache,
          profile,
          images,
          documentTotal=Some(total),
          pendingNotes=pending,
          endnotes=Some(endnotes),
          flushFootnotes=index == flow.sectionBreaks.length(),
          resolveBodyFields=false,
        )
        (pagination, stories, problems)
      } else {
        (first, first_stories, first_problems)
      }
      section_numbering.push(numbering)
      pending = pagination.notePending[pagination.noteCursor:].to_owned()
      continuation = if flow.sectionBreaks
        .get(index)
        .map(section => section.kind == "continuous") ==
        Some(true) {
        pagination.section_continuation()
      } else {
        None
      }
      for page, frame in pagination.pages {
        if page == 0 && joined {
          let prior = combined.pages.last().unwrap()
          lines += frame.lines.length() - prior.lines.length()
          combined.pages[combined.pages.length() - 1] = frame
          let notes = stories[page].filter(line => line.container == -3)
          running[running.length() - 1].append(notes)
          lines += notes.length()
          guard lines <= 32768 else {
            @failure.reject(
              "limit-exceeded", "Section layout exceeds line budget",
            )
          }
          continue
        }
        lines += frame.lines.length() + stories[page].length()
        guard combined.pages.length() < 1024 && lines <= 32768 else {
          @failure.reject(
            "limit-exceeded", "Section layout exceeds page or line budget",
          )
        }
        let borders = part.pageBorders.fills(part.page, page)
        combined.pages.push({
          ..frame,
          pageBorders: if part.pageBorders.zOrder == "front" {
            borders
          } else {
            []
          },
          fills: if part.pageBorders.zOrder == "back" {
            borders + frame.fills
          } else {
            frame.fills
          },
        })
        contexts.push((numbering, page))
        page_sections.push(Some((index, page)))
      }
      running.append(if joined { stories[1:].to_owned() } else { stories })
      diagnostics.append(problems)
      numbering = {
        ..numbering,
        start: numbering.start + pagination.pages.length().to_int64(),
      }
    }
    let (values, problems) = combined.body_field_values(
      fields,
      flow,
      fixed,
      contexts~,
    )
    diagnostics.append(problems)
    let (updated, stable) = body.resolve_body_fields(
      values,
      combined.pages.length(),
    )
    if stable && total == combined.pages.length() {
      return (
        combined.pages,
        running,
        diagnostics,
        section_numbering,
        page_sections,
      )
    }
    if attempt == 7 {
      diagnostics.push(
        "unsupported-layout:section-field-reflow-did-not-converge",
      )
      return (
        combined.pages,
        running,
        diagnostics,
        section_numbering,
        page_sections,
      )
    }
    body = updated
    total = combined.pages.length()
  }
  abort("unreachable")
}
