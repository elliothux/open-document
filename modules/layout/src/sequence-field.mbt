///|
pub(all) struct SequenceField {
  sequence : String
  format : String
  restart : Int32?
  repeat : Bool
  headingLevel : Int32?
  hidden : Bool
}

///|
pub fn SequenceField::parse(
  code : String,
) -> SequenceField raise @failure.Failure {
  let parts = code.split(":").to_array()
  guard parts.length() >= 2 &&
    parts.length() <= 6 &&
    parts[0] == "SEQ" &&
    !parts[1].is_empty() &&
    parts[1].length() <= 40 &&
    parts[1]
    .iter()
    .all(c => {
      c == '_' ||
      c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      (!c.is_ascii() && @ucd.non_ascii_id_continue.contains(c))
    }) &&
    parts[1]
    .get_char(0)
    .map(c => {
      c == '_' ||
      c.is_ascii_alphabetic() ||
      (!c.is_ascii() && @ucd.non_ascii_id_start.contains(c))
    })
    .unwrap_or(false) else {
    @failure.reject("unsupported-layout", "Invalid sequence field identifier")
  }
  let mut format = ""
  let mut restart : Int32? = None
  let mut repeat = false
  let mut headingLevel : Int32? = None
  let mut hidden = false
  for part in parts[2:] {
    if part == "hidden" && !hidden {
      hidden = true
    } else if part.has_prefix("heading=") && headingLevel is None {
      let value = sequence_option_number(part[8:], 9)
      guard value >= 1 else {
        @failure.reject("unsupported-layout", "Invalid sequence heading level")
      }
      headingLevel = Some(value)
    } else if part == "repeat" && !repeat && restart is None {
      repeat = true
    } else if part.has_prefix("restart=") && !repeat && restart is None {
      restart = Some(sequence_option_number(part[8:], 2147483647))
    } else if format.is_empty() &&
      ["decimal", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman"].contains(
        part.to_owned(),
      ) {
      format = part.to_owned()
    } else {
      @failure.reject("unsupported-layout", "Invalid sequence field options")
    }
  }
  guard !hidden || format.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Hidden sequence results require no explicit format",
    )
  }
  {
    sequence: parts[1].to_owned(),
    format,
    restart,
    repeat,
    headingLevel,
    hidden,
  }
}

///|
fn sequence_option_number(
  digits : StringView,
  maximum : Int32,
) -> Int32 raise @failure.Failure {
  guard !digits.is_empty() &&
    digits.length() <= 10 &&
    digits.iter().all(c => c.is_ascii_digit()) else {
    @failure.reject("unsupported-layout", "Invalid sequence counter option")
  }
  let mut value = 0L
  for c in digits.iter() {
    value = value * 10L + (c.to_int() - 48).to_int64()
  }
  guard value <= maximum.to_int64() else {
    @failure.reject("unsupported-layout", "Sequence option exceeds limits")
  }
  value.to_int()
}

///|
pub fn SequenceField::code(self : SequenceField) -> String {
  "SEQ:" +
  self.sequence +
  (if self.format.is_empty() { "" } else { ":" + self.format }) +
  (if self.repeat {
    ":repeat"
  } else {
    self.restart.map(n => ":restart=" + n.to_string()).unwrap_or("")
  }) +
  self.headingLevel.map(n => ":heading=" + n.to_string()).unwrap_or("") +
  (if self.hidden { ":hidden" } else { "" })
}

///|
fn SequenceField::text(
  self : SequenceField,
  value : Int64,
) -> String raise @failure.Failure {
  if self.hidden {
    return ""
  }
  PageNumbering::new(
    start=value,
    format=if self.format.is_empty() { "decimal" } else { self.format },
  ).field_text("PAGE", 0, 1)
}

///|
fn Flow::sequence_values(
  self : Flow,
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  let previous : Map[String, Int32] = Map([])
  let headings = Array::make(9, -1)
  let entries : Array[(SequenceField, (Int32, Int32), Int32, Int32)] = []
  let values : Map[(Int32, Int32), String] = Map([])
  for paragraph in self.body_field_paragraphs() {
    if self.outlineLevels.get(paragraph.id) is Some(level) {
      guard level >= 0 && level < 9 else {
        @failure.reject("unsupported-layout", "Invalid sequence outline level")
      }
      for i in level..<9 {
        headings[i] = entries.length() - 1
      }
    }
    for span in paragraph.spans {
      if !span.field.has_prefix("SEQ:") {
        continue
      }
      let field = SequenceField::parse(span.field)
      guard entries.length() < 4096 else {
        @failure.reject("limit-exceeded", "Sequence fields exceed limits")
      }
      entries.push(
        (
          field,
          (paragraph.id, span.node),
          previous.get(field.sequence).unwrap_or(-1),
          field.headingLevel.map(n => headings[n - 1]).unwrap_or(-1),
        ),
      )
      previous[field.sequence] = entries.length() - 1
    }
  }
  let cache : Map[(Int32, Int32), (Int64, Bool)] = Map([])
  let mut work = 0
  for index, (field, key, _, _) in entries {
    let pending : Array[(Int32, Int32, Bool)] = []
    let mut state = (1L, false)
    for current = index, boundary = -1 {
      work += 1
      guard work <= 1048576 && cache.length() <= 40960 else {
        @failure.reject(
          "limit-exceeded", "Sequence heading evaluation exceeds budget",
        )
      }
      if cache.get((current, boundary)) is Some(value) {
        state = value
        break
      }
      let (item, _, prior, heading) = entries[current]
      if item.restart is Some(start) {
        state = (start.to_int64(), true)
        cache[(current, boundary)] = state
        break
      }
      let lower = boundary.max(heading)
      if prior <= lower {
        state = (1L, !item.repeat)
        cache[(current, boundary)] = state
        break
      }
      pending.push((current, boundary, item.repeat))
      continue prior, lower
    }
    for (current, boundary, repeat) in pending.rev() {
      if !repeat {
        state = (if state.1 { state.0 + 1L } else { 1L }, true)
      }
      cache[(current, boundary)] = state
    }
    values[key] = field.text(state.0)
  }
  values
}
