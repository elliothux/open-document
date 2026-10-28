///|
pub(all) struct NoteReference {
  bookmark : String
  hyperlink : Bool
  relative : Bool
  superscript : Bool
}

///|
pub fn NoteReference::parse(
  code : String,
) -> NoteReference raise @failure.Failure {
  let parts = code.split(":").to_array()
  guard parts.length() >= 2 && parts[0] == "NOTEREF" else {
    @failure.reject("unsupported-layout", "Invalid note reference")
  }
  let mut superscript = false
  let options = ["PAGEREF", parts[1].to_owned()]
  for option in parts[2:] {
    if option == "superscript" && !superscript {
      superscript = true
    } else {
      options.push(option.to_owned())
    }
  }
  let reference = PageReference::parse(options.join(":"))
  guard reference.format.is_empty() else {
    @failure.reject("unsupported-layout", "Invalid note reference option")
  }
  {
    bookmark: reference.bookmark,
    hyperlink: reference.hyperlink,
    relative: reference.relative,
    superscript,
  }
}

///|
pub fn NoteReference::code(self : NoteReference) -> String {
  "NOTEREF:" +
  self.bookmark +
  (if self.superscript { ":superscript" } else { "" }) +
  (if self.hyperlink { ":hyperlink" } else { "" }) +
  (if self.relative { ":relative" } else { "" })
}

///|
fn Flow::note_reference_values(
  self : Flow,
) -> Map[(Int32, Int32), String] raise @failure.Failure {
  let paragraphs = self.body_field_paragraphs()
  let order = Map::from_array(paragraphs.mapi((index, p) => (p.id, index)))
  let anchors : Array[(Int32, Int32, String)] = []
  let fields : Array[(Int32, Int32, Int32, NoteReference)] = []
  let mut work = 0
  for p in paragraphs {
    let mut offset = 0
    for span in p.spans {
      work += 1
      guard work <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Note reference lookup exceeds budget",
        )
      }
      if span.field.has_prefix("NOTE:") {
        anchors.push((p.id, offset, span.text))
      } else if span.field.has_prefix("NOTEREF:") {
        fields.push((p.id, span.node, offset, NoteReference::parse(span.field)))
      }
      offset += span.logical_text().length()
    }
  }
  let result : Map[(Int32, Int32), String] = Map([])
  for (paragraph, node, offset, reference) in fields {
    let mut text = "Error! Bookmark not defined."
    if self.bookmarks.get(reference.bookmark.to_lower())
      is Some((start_p, start, end_p, end)) &&
      order.get(start_p) is Some(first) &&
      order.get(end_p) is Some(last) {
      for (target, at, label) in anchors {
        work += 1
        guard work <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Note reference lookup exceeds budget",
          )
        }
        let index = order[target]
        if index >= first &&
          index <= last &&
          (target != start_p || at >= start) &&
          (target != end_p || at < end) {
          text = if reference.relative {
            if first < order[paragraph] ||
              (start_p == paragraph && start <= offset) {
              "above"
            } else {
              "below"
            }
          } else {
            label
          }
          break
        }
      }
    }
    result[(paragraph, node)] = text
  }
  result
}
