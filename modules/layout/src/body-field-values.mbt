///|
fn Pagination::body_field_values(
  self : Pagination,
  fields : Map[(Int32, Int32), String],
  flow : Flow,
  fixed_values : Map[(Int32, Int32), String],
  contexts~ : Array[(PageNumbering, Int32)] = [],
  noteRunning~ : Array[Array[Line]] = [],
) -> (Map[(Int32, Int32), String], Array[String]) raise @failure.Failure {
  let values : Map[(Int32, Int32), String] = Map([])
  let diagnostics : Array[String] = []
  if fields.is_empty() {
    return (values, diagnostics)
  }
  let note_values = self.page_note_values(flow, noteRunning)
  for key, value in note_values {
    values[key] = value
  }
  let note_references = if note_values.is_empty() {
    Map([])
  } else {
    flow.resolve_body_fields(note_values, self.pages.length()).0.note_reference_values()
  }
  let references : Map[(Int32, Int32), PageReference] = Map([])
  for key, code in fields {
    if code.has_prefix("PAGEREF:") {
      references[key] = PageReference::parse(code)
    }
  }
  let origins : Map[(Int32, Int32), Hit] = Map([])
  let mut work = 0
  for page, frame in self.pages {
    for index, line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          let key = (line.paragraph, source.node)
          guard fields.get(key) is Some(code) else { continue }
          if code.has_prefix("NOTE:") {
            continue
          } else if note_references.get(key) is Some(text) {
            values[key] = text
          } else if references.get(key) is Some(reference) {
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
          } else if code.has_prefix("REF:") || code.has_prefix("CITATION:") {
            values[key] = run.text
          } else if fixed_values.get(key) is Some(text) {
            values[key] = text
          } else if !values.contains(key) {
            let (numbering, position) = contexts
              .get(page)
              .unwrap_or((flow.pageNumbering, page))
            values[key] = numbering.field_text(
              code,
              position,
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
    if flow.bookmarks.get(name) is Some((paragraph, offset, _, _)) &&
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
    let target = targets.get(name).bind(value => value)
    values[key] = if !reference.relative &&
      target is Some(target) &&
      contexts.get(target.page) is Some((numbering, position)) {
      numbering.field_text(reference.page_code(), position, self.pages.length())
    } else {
      reference.text(
        flow.pageNumbering,
        origins.get(key),
        target,
        self.pages.length(),
      )
    }
  }
  let (text, problems) = flow.text_reference_values(values)
  for key, value in text {
    values[key] = value
  }
  diagnostics.append(problems)
  (values, diagnostics)
}
