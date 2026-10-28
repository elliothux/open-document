///|
fn note_reference_counts(
  document : @xml.Document,
) -> Map[(String, String), Int32] raise @failure.Failure {
  let result : Map[(String, String), Int32] = Map([])
  for node in document.nodes() {
    if note_reference(node) {
      let kind = if node.name == "footnoteReference" {
        "footnote"
      } else {
        "endnote"
      }
      let key = (
        kind,
        note_key(node.attribute("id", uri=word_uri).unwrap_or("")),
      )
      result[key] = result.get(key).unwrap_or(0) + 1
    }
  }
  result
}

///|
// Main-story reference removal and its content part share one source transaction.
fn Session::note_transition(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
) -> (Map[String, @xml.Document], Map[String, Array[@xml.Edit]], Int32) raise @failure.Failure {
  if !self.document().nodes().any(note_reference) {
    return (parts, Map([]), 0)
  }
  let before = note_reference_counts(self.document())
  let after = note_reference_counts(document)
  let removed : Set[(String, String)] = Set([])
  for key, count in before {
    if after.get(key).unwrap_or(0) < count {
      guard count == 1 && after.get(key).unwrap_or(0) == 0 else {
        @failure.reject(
          "protected-content", "Repeated note references require reference-specific deletion",
        )
      }
      removed.add(key)
    }
  }
  if removed.is_empty() {
    return (parts, Map([]), 0)
  }
  for part in self.style_part_names() {
    if part == self.main {
      continue
    }
    for node in self.part_xml(part).nodes() {
      if note_reference(node) {
        let kind = if node.name == "footnoteReference" {
          "footnote"
        } else {
          "endnote"
        }
        guard !removed.contains(
          (kind, note_key(node.attribute("id", uri=word_uri).unwrap_or(""))),
        ) else {
          @failure.reject(
            "protected-content", "Note reference belongs to another content story",
          )
        }
      }
    }
  }
  let next = parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let mut bytes = 0
  for kind in ["footnote", "endnote"] {
    let keys = removed.to_array().filter(key => key.0 == kind).map(key => key.1)
    if keys.is_empty() {
      continue
    }
    guard self.note_source(kind) is Some(original) else {
      @failure.reject(
        "protected-content", "Missing note content prevents reference deletion",
      )
    }
    for key in keys {
      guard original.entries.iter().find_first(note => note.key == key)
        is Some(note) &&
        note.reason.is_empty() else {
        @failure.reject(
          "protected-content", "Structured or opaque note content is protected",
        )
      }
    }
    let candidate = parts.get(original.part).unwrap_or(original.document)
    let view = { ..self, parts, }
    guard view.note_source(kind) is Some(source) else {
      @failure.reject("protected-content", "Note content ownership changed")
    }
    let changes : Array[@xml.SourceChange] = source.entries
      .filter(note => keys.contains(note.key))
      .map(note => {
        let node = source.tree.nodes[note.node]
        {
          node: 0,
          offset: node.start - source.tree.nodes[0].start,
          length: node.end - node.start,
          xml: "",
        }
      })
    if changes.is_empty() {
      continue
    }
    let (updated, step) = candidate.edit_source(changes)
    let count = edit_bytes(step)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Note input exceeds history budget")
    }
    bytes += count
    next[original.part] = updated
    edits[original.part] = [step]
  }
  (next, edits, bytes)
}
