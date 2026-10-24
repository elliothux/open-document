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
    guard ["nextPage", "oddPage", "evenPage"].contains(section.kind) else {
      @failure.reject(
        "unsupported-layout", "This section break requires continuous section layout",
      )
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
) -> (Array[PageFrame], Array[Array[Line]], Array[String]) raise @failure.Failure {
  let fields = flow.body_fields()
  let fixed = flow.sequence_values()
  if fields.values().any(code => code.has_prefix("NOTEREF:")) {
    for key, value in flow.note_reference_values() {
      fixed[key] = value
    }
  }
  let mut body = flow.resolve_body_fields(fixed, 1).0
  let mut total = 1
  for attempt in 0..<8 {
    let combined = Pagination::new(flow.page)
    combined.pages.clear()
    let running : Array[Array[Line]] = []
    let contexts : Array[(PageNumbering, Int)] = []
    let diagnostics : Array[String] = []
    let mut numbering = flow.pageNumbering
    let mut lines = 0
    let mut pending : Array[(Line, Double)] = []
    for index in 0..<=flow.sectionBreaks.length() {
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
          contexts.push((numbering, 0))
          numbering = { ..numbering, start: numbering.start + 1L, }
        }
        numbering = {
          ..section.pageNumbering,
          start: if section.restartNumbering {
            start + (if parity >= 0 && start % 2L != parity { 1L } else { 0L })
          } else {
            numbering.start
          },
        }
      }
      numbering.validate()
      let part = body.section_body(index, numbering)
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
      pending = pagination.notePending[pagination.noteCursor:].to_owned()
      for page, frame in pagination.pages {
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
      }
      running.append(stories)
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
      return (combined.pages, running, diagnostics)
    }
    if attempt == 7 {
      diagnostics.push(
        "unsupported-layout:section-field-reflow-did-not-converge",
      )
      return (combined.pages, running, diagnostics)
    }
    body = updated
    total = combined.pages.length()
  }
  abort("unreachable")
}
