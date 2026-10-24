///|
pub(all) struct TextReference {
  bookmark : String
  hyperlink : Bool
  numbered : Bool
}

///|
pub fn TextReference::parse(
  code : String,
) -> TextReference raise @failure.Failure {
  guard code.has_prefix("REF:") else {
    @failure.reject("unsupported-layout", "Invalid text reference")
  }
  let parts = code[4:].split(":").to_array()
  let mut numbered = false
  let options = [parts[0].to_owned()]
  for option in parts[1:] {
    if option == "number" && !numbered {
      numbered = true
    } else {
      options.push(option.to_owned())
    }
  }
  let reference = PageReference::parse("PAGEREF:" + options.join(":"))
  guard reference.format.is_empty() && !reference.relative else {
    @failure.reject("unsupported-layout", "Invalid text reference option")
  }
  { bookmark: reference.bookmark, hyperlink: reference.hyperlink, numbered, }
}

///|
pub fn TextReference::code(self : TextReference) -> String {
  "REF:" +
  self.bookmark +
  (if self.numbered { ":number" } else { "" }) +
  (if self.hyperlink { ":hyperlink" } else { "" })
}

///|
fn Flow::text_reference_values(
  self : Flow,
  values : Map[(Int, Int), String],
) -> (Map[(Int, Int), String], Array[String]) raise @failure.Failure {
  let paragraphs = self.body_field_paragraphs()
  let by_id = Map::from_array(paragraphs.map(p => (p.id, p)))
  let references : Map[(Int, Int), Span] = Map([])
  for p in paragraphs {
    for span in p.spans {
      if span.field.has_prefix("REF:") {
        references[(p.id, span.node)] = span
      }
    }
  }
  let resolved : Map[(Int, Int), String] = Map([])
  let failed : Map[(Int, Int), Bool] = Map([])
  let active : Map[(Int, Int), Bool] = Map([])
  let mut work = 0
  fn evaluate(key : (Int, Int), depth : Int) -> String raise @failure.Failure {
    guard !failed.contains(key) else {
      @failure.reject("unsupported-layout", "invalid-text-reference-dependency")
    }
    if resolved.get(key) is Some(value) {
      return value
    }
    guard depth <= 64 && !active.get(key).unwrap_or(false) else {
      @failure.reject("unsupported-layout", "cyclic-text-reference")
    }
    active[key] = true
    defer {
      active[key] = false
    }
    let reference = TextReference::parse(references[key].field)
    guard self.bookmarks.get(reference.bookmark.to_lower())
      is Some((start_p, start, end_p, end)) else {
      return "Error! Reference source not found."
    }
    guard by_id.get(start_p) is Some(paragraph) &&
      start >= 0 &&
      (start_p != end_p || end >= start) else {
      @failure.reject("unsupported-layout", "text-reference-target-structure")
    }
    if reference.numbered {
      work += paragraph.spans.length()
      guard work <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Number reference lookup exceeds budget",
        )
      }
      guard start <=
        paragraph.spans.fold(init=0, (sum, span) => {
          sum + span.logical_text().length()
        }) else {
        @failure.reject("unsupported-layout", "text-reference-target-boundary")
      }
      let text = paragraph.marker
        .bind(marker => marker.referenceText)
        .unwrap_or("0")
      guard text.length() <= 256 &&
        text
        .iter()
        .all(c => c >= ' ' && c != '\u007f' && c != '\u2028' && c != '\u2029') else {
        @failure.reject("unsupported-layout", "number-reference-target-control")
      }
      resolved[key] = text
      return text
    }
    guard start_p == end_p else {
      @failure.reject("unsupported-layout", "text-reference-target-structure")
    }
    let out = StringBuilder()
    let mut offset = 0
    let mut units = 0
    for span in paragraph.spans {
      work += 1
      guard work <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Text reference lookup exceeds budget",
        )
      }
      let length = span.logical_text().length()
      let left = start.max(offset) - offset
      let right = end.min(offset + length) - offset
      if left < right {
        guard span.drawing is None else {
          @failure.reject("unsupported-layout", "text-reference-target-drawing")
        }
        let text = if span.field.has_prefix("REF:") {
          evaluate((paragraph.id, span.node), depth + 1)
        } else if !span.field.is_empty() {
          values.get((paragraph.id, span.node)).unwrap_or(span.text)
        } else {
          guard span.text.get_view(start=left, end=right) is Some(text) else {
            @failure.reject(
              "unsupported-layout", "text-reference-target-boundary",
            )
          }
          text.to_owned()
        }
        work += text.length()
        units += text.length()
        guard work <= 1048576 && units <= 4096 else {
          @failure.reject(
            "limit-exceeded", "Text reference results exceed budget",
          )
        }
        guard text
          .iter()
          .all(c => c >= ' ' && c != '\u007f' && c != '\u2028' && c != '\u2029') else {
          @failure.reject("unsupported-layout", "text-reference-target-control")
        }
        out.write_string(text)
      }
      offset += length
    }
    guard end <= offset else {
      @failure.reject("unsupported-layout", "text-reference-target-boundary")
    }
    let text = out.to_string()
    resolved[key] = text
    text
  }
  let diagnostics : Array[String] = []
  for key, span in references {
    let text = evaluate(key, 0) catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => {
        failed[key] = true
        let reason = "unsupported-layout:" + message
        if !diagnostics.contains(reason) {
          diagnostics.push(reason)
        }
        span.text
      }
    }
    resolved[key] = text
  }
  (resolved, diagnostics)
}
