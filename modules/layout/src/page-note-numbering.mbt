///|
fn Pagination::page_note_values(
  self : Pagination,
  flow : Flow,
  running : Array[Array[Line]],
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  let values : Map[(Int32, Int32), String] = Map([])
  if !flow.notes.any(note => note.numbering.restart == "eachPage") {
    return values
  }
  let notes = Map::from_array(
    flow.notes
    .filter(note => note.kind == "footnote")
    .map(note => ((note.paragraph, note.node), note)),
  )
  let origins : Map[(Int32, Int32), Int32] = Map([])
  let first_content : Map[Int32, Int32] = Map([])
  let first_ids = Set::from_array(
    flow.notes
    .filter(note => note.kind == "footnote")
    .map(note => note.content[0].id),
  )
  let mut work = 0
  for page, frame in self.pages {
    for line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          work += 1
          guard work <= 1048576 else {
            @failure.reject("limit-exceeded", "Note page lookup exceeds budget")
          }
          let key = (line.paragraph, source.node)
          if notes.contains(key) && !origins.contains(key) {
            origins[key] = page
          }
        }
      }
    }
  }
  for page, lines in running {
    for line in lines {
      if first_ids.contains(line.paragraph) &&
        !first_content.contains(line.paragraph) {
        first_content[line.paragraph] = page
      }
    }
  }
  let counters : Map[Int32, Int64] = Map([])
  let seen : Set[(Int32, Int32)] = Set([])
  for paragraph in flow.body_field_paragraphs() {
    for span in paragraph.spans {
      let key = (paragraph.id, span.node)
      guard !seen.contains(key) &&
        notes.get(key) is Some(note) &&
        origins.get(key) is Some(page) else {
        continue
      }
      seen.add(key)
      let value = if note.numbering.restart == "eachPage" {
        counters.get(page).unwrap_or(0L) + 1L
      } else {
        note.numbering.value
      }
      counters[page] = value
      // A note deferred wholly to the following page shares that page's next ordinal.
      if first_content.get(note.content[0].id) == Some(page + 1) {
        counters[page + 1] = value
      }
      if note.numbering.restart == "eachPage" {
        values[key] = { ..note.numbering, value, }.text()
      }
    }
  }
  values
}
