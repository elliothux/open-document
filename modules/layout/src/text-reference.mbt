///|
pub(all) struct TextReference {
  bookmark : String
  hyperlink : Bool
  numbering : String
  relative : Bool
  separator : String
}

///|
pub fn TextReference::parse(
  code : String,
) -> TextReference raise @failure.Failure {
  guard code.has_prefix("REF:") else {
    @failure.reject("unsupported-layout", "Invalid text reference")
  }
  // The terminal separator payload can contain literal colons without escaping.
  let (source, separator) = match code.find(":separator=") {
    Some(index) => (code[:index].to_owned(), code[index + 11:].to_owned())
    None => (code, "")
  }
  guard separator.length() <= 32 &&
    !separator.has_prefix("\\") &&
    !separator.has_suffix("\\") &&
    separator
    .iter()
    .all(c => {
      c >= ' ' &&
      !(c >= '\u007f' && c <= '\u009f') &&
      c != '\u2028' &&
      c != '\u2029'
    }) else {
    @failure.reject(
      "unsupported-layout", "Invalid reference numbering separator",
    )
  }
  let parts = source[4:].split(":").to_array()
  let mut numbering = ""
  let options = [parts[0].to_owned()]
  for option in parts[1:] {
    if ["number", "numberRelative", "numberFull"].contains(option.to_owned()) &&
      numbering.is_empty() {
      numbering = option.to_owned()
    } else {
      options.push(option.to_owned())
    }
  }
  let reference = PageReference::parse("PAGEREF:" + options.join(":"))
  guard reference.format.is_empty() else {
    @failure.reject("unsupported-layout", "Invalid text reference option")
  }
  {
    bookmark: reference.bookmark,
    hyperlink: reference.hyperlink,
    numbering,
    relative: reference.relative,
    separator,
  }
}

///|
pub fn TextReference::code(self : TextReference) -> String {
  "REF:" +
  self.bookmark +
  (if self.numbering.is_empty() { "" } else { ":" + self.numbering }) +
  (if self.hyperlink { ":hyperlink" } else { "" }) +
  (if self.relative { ":relative" } else { "" }) +
  (if self.separator.is_empty() { "" } else { ":separator=" + self.separator })
}

///|
fn Flow::text_reference_values(
  self : Flow,
  values : Map[(Int, Int), String],
) -> (Map[(Int, Int), String], Array[String]) raise @failure.Failure {
  let paragraphs = self.body_field_paragraphs()
  let by_id = Map::from_array(paragraphs.map(p => (p.id, p)))
  let references : Map[(Int, Int), Span] = Map([])
  let order : Map[Int, Int] = Map([])
  let offsets : Map[(Int, Int), Int] = Map([])
  for index, p in paragraphs {
    order[p.id] = index
    let mut offset = 0
    for span in p.spans {
      if span.field.has_prefix("REF:") {
        references[(p.id, span.node)] = span
        offsets[(p.id, span.node)] = offset
      }
      offset += span.logical_text().length()
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
    if !reference.numbering.is_empty() || reference.relative {
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
      // ONLYOFFICE REF \p compares document positions, including across pages and RTL.
      let position = if order[start_p] < order[key.0] ||
        (start_p == key.0 && start <= offsets[key]) {
        "above"
      } else {
        "below"
      }
      if reference.numbering.is_empty() {
        resolved[key] = position
        return position
      }
      guard paragraph.marker.bind(marker => marker.numbering) is Some(numbering) else {
        resolved[key] = "0"
        return "0"
      }
      let text = numbering.reference_text(
        reference.numbering,
        by_id[key.0].marker.bind(marker => marker.numbering),
        reference.separator,
      )
      work += text.length()
      guard work <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Number reference lookup exceeds budget",
        )
      }
      let result = text +
        (if reference.relative && numbering.numeric {
          " " + position
        } else {
          ""
        })
      resolved[key] = result
      return result
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
        guard !span.field.has_prefix("NOTE:") else {
          @failure.reject("unsupported-layout", "text-reference-target-note")
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
