///|
fn style_reference_level(code : String) -> Int32 raise @failure.Failure {
  guard code.has_prefix("STYLEREF:") &&
    code.length() == 10 &&
    code[9] >= '1' &&
    code[9] <= '9' else {
    @failure.reject("unsupported-layout", "Invalid chapter style reference")
  }
  code[9].to_int() - 48
}

///|
fn Flow::style_reference_values(
  self : Flow,
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  let paragraphs = self.body_field_paragraphs()
  let first : Array[Paragraph?] = Array::make(9, None)
  let previous : Array[Paragraph?] = Array::make(9, None)
  for p in paragraphs {
    if self.outlineLevels.get(p.id) is Some(level) {
      guard level >= 0 && level < 9 else {
        @failure.reject("unsupported-layout", "Invalid chapter outline level")
      }
      if first[level] is None {
        first[level] = Some(p)
      }
    }
  }
  let values : Map[(Int32, Int32), String] = Map([])
  for p in paragraphs {
    if self.outlineLevels.get(p.id) is Some(level) {
      previous[level] = Some(p)
    }
    for span in p.spans {
      if !span.field.has_prefix("STYLEREF:") {
        continue
      }
      let level = style_reference_level(span.field) - 1
      guard values.length() < 4096 else {
        @failure.reject("limit-exceeded", "Chapter references exceed budget")
      }
      let target = match previous[level] {
        Some(_) as value => value
        None => first[level]
      }
      let text = match target {
        Some(target) =>
          target.marker
          .bind(marker => marker.numbering)
          .map(numbering => numbering.reference_text("number", None, ""))
          .unwrap_or("0")
        None => "Error! No text of specified style in document."
      }
      values[(p.id, span.node)] = text
    }
  }
  values
}

///|
fn Flow::fixed_body_field_values(
  self : Flow,
  fields : Map[(Int32, Int32), String],
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  let values = self.sequence_values()
  if fields.values().any(code => code.has_prefix("NOTEREF:")) {
    for key, value in self.note_reference_values() {
      values[key] = value
    }
  }
  if fields.values().any(code => code.has_prefix("STYLEREF:")) {
    for key, value in self.style_reference_values() {
      values[key] = value
    }
  }
  values
}
