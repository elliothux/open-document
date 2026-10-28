///|
fn push_running_link(
  content : Array[RunningContent],
  text : String,
  target : String,
) -> Unit {
  for index, piece in text.split("\n").to_array() {
    if index > 0 {
      push_running_text(content, "\n")
    }
    if piece.is_empty() {
      continue
    }
    let text = piece.to_owned()
    if content.last() is Some(Link(previous, value)) && value == target {
      content[content.length() - 1] = Link(previous + text, target)
    } else {
      content.push(Link(text, target))
    }
  }
}

///|
fn Session::running_links(
  self : Session,
  part : String?,
  paragraphs : Array[@layout.Paragraph],
) -> Map[Int32, String] raise @failure.Failure {
  let result : Map[Int32, String] = Map([])
  guard part is Some(part) else { return result }
  let tree = WordTree::new(self.part_xml(part))
  let relations = Map::from_array(
    self.relationships().filter(r => r.owner == part).map(r => (r.id, r)),
  )
  let bookmarks = WordTree::new(self.document()).bookmark_targets()
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if !result.contains(span.node) && span.field.is_empty() {
        if hyperlink_target(
            tree,
            tree.nodes[span.node].parent,
            relations,
            bookmarks,
          )
          is Some(target) {
          result[span.node] = target
        }
      }
    }
  }
  result
}
