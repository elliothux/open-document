///|
fn paginate_running(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> (Pagination, Array[Array[Line]], Int, Int, PaginationCache?, Array[String]) raise @failure.Failure {
  let (patterns, setups) = running_lines(probe, flow, cache, profile, images)
  let dynamic = [flow.headers, flow.footers].any(stories => {
    stories
    .values()
    .any(story => story.any(p => p.spans.any(span => !span.field.is_empty())))
  })
  let mut page_setups : Array[PageSetup] = []
  let mut prepared : Array[Array[Line]] = []
  for attempt in 0..<8 {
    let pagination = Pagination::new(setups[0], setups~, pageSetups=page_setups)
    let (reflowed, reused, next) = pagination.body(
      probe, flow, cache, profile, images,
    )
    let previous = pagination.pages.mapi((index, _) => {
      prepared
      .get(index)
      .unwrap_or(
        patterns[if index == 0 { 0 } else if index % 2 == 1 { 1 } else { 2 }],
      )
    })
    if !dynamic {
      return (pagination, previous, reflowed, reused, next, [])
    }
    let total = pagination.pages.length()
    let running : Array[Array[Line]] = []
    let actual : Array[PageSetup] = []
    let mut lines = pagination.count
    let mut stable = true
    for page in 0..<total {
      let (pattern, setup) = running_lines(
        probe,
        flow,
        cache,
        profile,
        images,
        page~,
        total~,
      )
      lines += pattern[0].length()
      guard lines <= 32768 else {
        @failure.reject(
          "limit-exceeded", "Repeated header and footer line budget exceeded",
        )
      }
      running.push(pattern[0])
      actual.push(setup[0])
      if setup[0].to_json() != pagination.page_at(page).to_json() {
        stable = false
      }
    }
    if stable {
      return (pagination, running, reflowed, reused, next, [])
    }
    if attempt == 7 {
      // Preserve the last complete layout; diagnostics keep uncertain output explicit.
      return (
        pagination,
        previous,
        reflowed,
        reused,
        next,
        ["unsupported-layout:running-field-reflow-did-not-converge"],
      )
    }
    page_setups = actual
    prepared = running
  }
  abort("unreachable")
}
