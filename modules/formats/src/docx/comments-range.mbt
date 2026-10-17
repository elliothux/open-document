///|
fn Session::restore_comments(
  self : Session,
  prepared : PreparedEdit,
) -> PreparedEdit raise @failure.Failure {
  let original = self.document()
  let before = WordTree::new(original)
  if !before.order.any(id => before.is_comment_marker(id)) {
    return prepared
  }
  let next = WordTree::new(prepared.document)
  let present : Map[String, Bool] = Map([])
  for id in next.order {
    if next.is_comment_marker(id) {
      let n = next.nodes[id]
      present[n.name + ":" + n.attribute("id", uri=word_uri).unwrap_or("")] = true
    }
  }
  let lost : Map[Int, Bool] = Map([])
  for anchor in before.comment_anchors() {
    if !anchor.reason.is_empty() {
      continue
    }
    for id in [anchor.start, anchor.end, Some(anchor.reference)] {
      if id is Some(id) &&
        !present.contains(before.nodes[id].name + ":" + anchor.key) {
        lost[id] = true
      }
    }
  }
  if lost.is_empty() {
    return prepared
  }
  let after = prepared.edit.after.unwrap()
  let (document, steps) = self.split_bookmark_boundary(prepared.document, after)
  let starts = StringBuilder()
  let ends = StringBuilder()
  let references = StringBuilder()
  for id in before.order {
    if !lost.contains(id) {
      continue
    }
    let marker = before.nodes[id]
    let markup = before.standalone_markup(original, id)
    match marker.name {
      "commentRangeStart" => starts.write_string(markup)
      "commentRangeEnd" => ends.write_string(markup)
      _ => {
        let properties = before
          .child(marker.parent, "rPr")
          .map(id => before.standalone_markup(original, id))
          .unwrap_or("")
        references.write_string(
          "<od:r xmlns:od=\"\{word_uri}\">\{properties}\{markup}</od:r>",
        )
      }
    }
  }
  let start = starts.to_string()
  let ending = ends.to_string() + references.to_string()
  let boundary = bookmark_boundary(document, after.focus, start + ending)
  let current = WordTree::new(document)
  let mut left = boundary.offset
  let mut right = boundary.offset
  for id, position in current.inline_marker_positions() {
    let node = current.nodes[id]
    if position.paragraph == after.focus.paragraph &&
      position.offset == after.focus.offset &&
      node.name != "commentReference" {
      left = left.min(node.start - current.nodes[position.paragraph].start)
      right = right.max(node.end - current.nodes[position.paragraph].start)
    }
  }
  let changes = if left == right || current.nodes[after.focus.paragraph].empty {
    [boundary]
  } else {
    let changes : Array[@xml.SourceChange] = []
    if !start.is_empty() {
      changes.push({ ..boundary, offset: left, xml: start, })
    }
    if !ending.is_empty() {
      changes.push({ ..boundary, offset: right, xml: ending, })
    }
    changes
  }
  let (candidate, step) = document.edit_source(changes)
  let xml = prepared.edit.xml.copy()
  xml.append(steps)
  xml.push(step)
  let bytes = xml.iter().fold(init=0, (sum, e) => sum + edit_bytes(e))
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "Comment anchor history exceeds budget")
  }
  {
    ..prepared,
    document: candidate,
    typing_text: None,
    edit: { ..prepared.edit, xml, bytes, },
  }
}
