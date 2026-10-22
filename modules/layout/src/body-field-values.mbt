///|
fn Pagination::body_field_values(
  self : Pagination,
  fields : Map[(Int, Int), String],
  flow : Flow,
  sequences : Map[(Int, Int), String],
) -> (Map[(Int, Int), String], Array[String]) raise @failure.Failure {
  let values : Map[(Int, Int), String] = Map([])
  let diagnostics : Array[String] = []
  if fields.is_empty() {
    return (values, diagnostics)
  }
  let references : Map[(Int, Int), PageReference] = Map([])
  for key, code in fields {
    if code.has_prefix("PAGEREF:") {
      references[key] = PageReference::parse(code)
    }
  }
  let origins : Map[(Int, Int), Hit] = Map([])
  let mut work = 0
  for page, frame in self.pages {
    for index, line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          let key = (line.paragraph, source.node)
          guard fields.get(key) is Some(code) else { continue }
          if references.get(key) is Some(reference) {
            if !origins.contains(key) {
              work += line.carets.length()
              guard work <= 1048576 else {
                @failure.reject(
                  "limit-exceeded", "Page reference target lookup exceeds budget",
                )
              }
              if line.carets
                .iter()
                .find_first(caret => caret.offset == run.start)
                is Some(caret) {
                origins[key] = line_hit(line, page, index, caret, "after")
              }
            }
            if line.repeated &&
              reference.relative &&
              !diagnostics.contains(
                "unsupported-layout:repeated-relative-page-reference",
              ) {
              diagnostics.push(
                "unsupported-layout:repeated-relative-page-reference",
              )
            }
          } else if sequences.get(key) is Some(text) {
            values[key] = text
          } else if !values.contains(key) {
            values[key] = flow.pageNumbering.field_text(
              code,
              page,
              self.pages.length(),
            )
          }
          if line.repeated &&
            (code == "PAGE" || code.has_prefix("PAGE:")) &&
            !diagnostics.contains("unsupported-layout:repeated-body-page-field") {
            diagnostics.push("unsupported-layout:repeated-body-page-field")
          }
        }
      }
    }
  }
  if values.length() + origins.length() != fields.length() {
    diagnostics.push("unsupported-layout:body-field-position-unavailable")
  }
  let targets : Map[String, Hit?] = Map([])
  for key, reference in references {
    let name = reference.bookmark.to_lower()
    if flow.bookmarks.get(name) is Some((paragraph, offset)) &&
      !targets.contains(name) {
      let mut found : Hit? = None
      let mut matched = false
      for page, frame in self.pages {
        for index, line in frame.lines {
          work += 1
          guard work <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Page reference target lookup exceeds budget",
            )
          }
          if line.paragraph != paragraph || line.container < 0 || line.repeated {
            continue
          }
          if line.start <= offset && offset <= line.end {
            work += line.carets.length()
            guard work <= 1048576 else {
              @failure.reject(
                "limit-exceeded", "Page reference target lookup exceeds budget",
              )
            }
            if line.carets.iter().find_first(caret => caret.offset == offset)
              is Some(caret) {
              found = Some(line_hit(line, page, index, caret, "after"))
              if offset < line.end || line.start == line.end {
                matched = true
                break
              }
            }
          }
        }
        if matched {
          break
        }
      }
      targets[name] = found
      if found is None &&
        !diagnostics.contains(
          "unsupported-layout:page-reference-target-unavailable",
        ) {
        diagnostics.push("unsupported-layout:page-reference-target-unavailable")
      }
    }
    values[key] = reference.text(
      flow.pageNumbering,
      origins.get(key),
      targets.get(name).bind(value => value),
      self.pages.length(),
    )
  }
  (values, diagnostics)
}
