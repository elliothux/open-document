///|
fn paginate_running(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
  previous~ : PaginationCache? = None,
  documentTotal~ : Int32? = None,
  pendingNotes~ : Array[NoteLine] = [],
  endnotes~ : Array[Note]? = None,
  flushFootnotes~ : Bool = true,
  resolveBodyFields~ : Bool = true,
  continuation~ : SectionContinuation? = None,
) -> (
  Pagination,
  Array[PageFrame],
  Int32,
  Int32,
  PaginationCache?,
  Array[String],
) raise @failure.Failure {
  let (patterns, setups) = running_lines(
    probe,
    flow,
    cache,
    profile,
    images,
    total=documentTotal.unwrap_or(1),
  )
  let fields = if resolveBodyFields { flow.body_fields() } else { Map([]) }
  let fixed_values = if fields.is_empty() {
    Map([])
  } else {
    flow.fixed_body_field_values(fields)
  }
  let mut body = if fields.is_empty() {
    flow
  } else {
    flow.resolve_body_fields(fixed_values, 1).0
  }
  let dynamic = [flow.headers, flow.footers].any(stories => {
    stories
    .values()
    .any(story => {
      story
      .all_paragraphs()
      .any(p => p.spans.any(span => !span.field.is_empty()))
    })
  })
  let mut page_setups : Array[PageSetup] = []
  let mut prepared : Array[PageFrame] = []
  for attempt in 0..<8 {
    let (pagination, frames, reflowed, reused, next) = column_body(
      probe,
      body,
      cache,
      profile,
      images,
      setups,
      page_setups,
      previous,
      pendingNotes~,
      endnotes~,
      flushFootnotes~,
      continuation~,
    )
    let notes : Array[Array[Line]] = []
    for index, lines in frames {
      if index % flow.columns.count == 0 {
        notes.push(lines.copy())
      } else {
        notes.last().unwrap().append(lines)
      }
    }
    pagination.finish_columns(frames)
    let reflowed = if frames.all(lines => lines.is_empty()) {
      reflowed
    } else {
      pagination.pages.length() - reused
    }
    let previous_frames = pagination.pages.mapi((index, _) => {
      prepared
      .get(index)
      .unwrap_or(
        patterns[if index == 0 { 0 } else if index % 2 == 1 { 1 } else { 2 }],
      )
    })
    let previous = previous_frames.mapi((index, frame) => {
      ..frame,
      lines: frame.lines + notes[index],
    })
    let total = pagination.pages.length()
    let (values, diagnostics) = pagination.body_field_values(
      fields,
      flow,
      fixed_values,
      noteRunning=previous.map(frame => frame.lines),
    )
    let (updated, body_stable) = if fields.is_empty() {
      (body, true)
    } else {
      body.resolve_body_fields(values, total)
    }
    if !dynamic {
      if body_stable || attempt == 7 {
        if !body_stable {
          diagnostics.push(
            "unsupported-layout:body-field-reflow-did-not-converge",
          )
        }
        return (pagination, previous, reflowed, reused, next, diagnostics)
      }
      body = updated
      continue
    }
    let running : Array[PageFrame] = []
    let actual : Array[PageSetup] = []
    let mut lines = pagination.count
    let mut stable = body_stable
    for page in 0..<total {
      let (pattern, setup) = running_lines(
        probe,
        flow,
        cache,
        profile,
        images,
        page~,
        total=documentTotal.unwrap_or(total),
      )
      lines += pattern[0].lines.length()
      guard lines <= 32768 else {
        @failure.reject(
          "limit-exceeded", "Repeated header and footer line budget exceeded",
        )
      }
      running.push(pattern[0])
      actual.push(setup[0])
      let actual_setup = if page == 0 &&
        continuation is Some(state) &&
        !state.empty {
        { ..setup[0], top: state.y, bottom: state.page.bottom, }
      } else {
        setup[0]
      }
      if actual_setup.to_json() != pagination.sheet_setup(page).to_json() {
        stable = false
      }
    }
    if stable {
      return (
        pagination,
        running.mapi((index, frame) => {
          ..frame,
          lines: frame.lines + notes[index],
        }),
        reflowed,
        reused,
        next,
        diagnostics,
      )
    }
    if attempt == 7 {
      // Preserve the last complete layout; diagnostics keep uncertain output explicit.
      return (
        pagination,
        previous,
        reflowed,
        reused,
        next,
        diagnostics +
        ["unsupported-layout:running-field-reflow-did-not-converge"],
      )
    }
    page_setups = actual
    prepared = running
    body = updated
  }
  abort("unreachable")
}
