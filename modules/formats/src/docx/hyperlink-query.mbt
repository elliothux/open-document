///|
fn check_hyperlink_target(target : String) -> Unit raise @failure.Failure {
  guard target.length() <= 2048 else {
    @failure.reject(
      "invalid-operation", "Hyperlink address exceeds 2048 UTF-16 units",
    )
  }
  let lower = target.to_lower()
  let prefix = if lower.has_prefix("https://") {
    8
  } else if lower.has_prefix("http://") || lower.has_prefix("mailto:") {
    7
  } else {
    0
  }
  guard prefix > 0 &&
    target.length() > prefix &&
    @xml.valid_text(target) &&
    target
    .iter()
    .all(c => {
      !c.is_whitespace() && c.to_int() > 32 && c.to_int() != 127 && c != '\\'
    }) else {
    @failure.reject(
      "invalid-operation", "Hyperlink requires a bounded HTTP, HTTPS or mailto address",
    )
  }
}

///|
fn WordTree::run_hyperlink(self : WordTree, run : Int) -> Int? {
  let parent = self.nodes[run].parent
  if parent >= 0 &&
    self.nodes[parent].uri == word_uri &&
    self.nodes[parent].name == "hyperlink" {
    Some(parent)
  } else {
    None
  }
}

///|
fn Session::hyperlink_runs(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
) -> Array[Int] {
  let selected : Array[Int] = []
  let seen : Map[Int, Bool] = Map([])
  let texts = docx_texts(tree)
  let collapsed = range.start.paragraph == range.end.paragraph &&
    range.start.offset == range.end.offset
  if collapsed &&
    self.selection == Some({ anchor: range.start, focus: range.end, }) &&
    self.typing_text is Some(id) &&
    texts
    .iter()
    .find_first(item => item.id == id && item.paragraph == range.start.paragraph)
    is Some(item) {
    return [item.run]
  }
  for p in range.paragraphs {
    let items = texts.filter(item => item.paragraph == p)
    let start = if p == range.start.paragraph { range.start.offset } else { 0 }
    let end = if p == range.end.paragraph {
      range.end.offset
    } else {
      0x7fffffff
    }
    let mut offset = 0
    for index, item in items {
      let count = inline_text(tree.nodes[item.id]).length()
      let hit = if collapsed {
        start < offset + count ||
        (start == offset + count && range.start.affinity == "before") ||
        index == items.length() - 1
      } else {
        start < offset + count && end > offset
      }
      if hit && !seen.contains(item.run) {
        selected.push(item.run)
        seen[item.run] = true
      }
      if hit && collapsed {
        break
      }
      offset += count
    }
    if items.is_empty() && tree.paragraph_runs(p).get(0) is Some(run) {
      selected.push(run)
    }
  }
  selected
}

///|
fn hyperlink_target(
  tree : WordTree,
  run : Int,
  links : Map[String, @opc.Relationship],
) -> String? raise @failure.Failure {
  guard tree.run_hyperlink(run) is Some(id) else { return None }
  tree.check_hyperlink(id)
  let node = tree.nodes[id]
  guard node.attribute("anchor", uri=word_uri) is None &&
    node.attribute("docLocation", uri=word_uri) is None else {
    @failure.reject(
      "protected-content", "Bookmark and document-location hyperlink targets require editing support",
    )
  }
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let key = node.attribute("id", uri=rel_uri).unwrap_or("")
  guard links.get(key) is Some(link) &&
    link.external &&
    link.kind == rel_uri + "/hyperlink" else {
    @failure.reject(
      "protected-content", "Unresolved or unsupported hyperlink relationship",
    )
  }
  check_hyperlink_target(link.target)
  Some(link.target)
}

///|
fn Session::hyperlink_range(
  self : Session,
  document : @xml.Document,
  selection : Selection,
) -> ParagraphRange raise @failure.Failure {
  let range = self.formatting_range(document, selection)
  if range.start.paragraph != range.end.paragraph ||
    range.start.offset != range.end.offset {
    return range
  }
  let tree = WordTree::new(document)
  guard self
    .hyperlink_runs(tree, range)
    .get(0)
    .bind(run => tree.run_hyperlink(run))
    is Some(link) else {
    return range
  }
  let mut start = 0
  let mut length = 0
  let mut seen = false
  for
    item in docx_texts(tree).filter(item => {
      item.paragraph == range.start.paragraph
    }) {
    let count = inline_text(tree.nodes[item.id]).length()
    if tree.run_hyperlink(item.run) == Some(link) {
      seen = true
      length += count
    } else if !seen {
      start += count
    }
  }
  {
    ..range,
    start: { ..range.start, offset: start, },
    end: { ..range.end, offset: start + length, },
  }
}

///|
fn Session::hyperlink_summary(
  self : Session,
  tree : WordTree,
  range : ParagraphRange?,
  reason : String,
) -> Json {
  let unavailable = fn(reason : String) -> Json {
    { "target": Json::null(), "mixed": false, "reason": reason }
  }
  guard range is Some(range) else { return unavailable(reason) }
  try {
    let links = self.hyperlink_relationships()
    let values = self
      .hyperlink_runs(tree, range)
      .map(run => hyperlink_target(tree, run, links))
    let first = values.get(0).unwrap_or(None)
    let mixed = values.any(v => v != first)
    {
      "target": if mixed {
        Json::null()
      } else {
        first.map(value => Json(value)).unwrap_or(Json::null())
      },
      "mixed": mixed,
      "reason": "",
    }
  } catch {
    @failure.Failure(message~, ..) => unavailable(message)
  }
}

///|
fn Session::hyperlink_relationships(
  self : Session,
) -> Map[String, @opc.Relationship] raise @failure.Failure {
  Map::from_array(
    self
    .relationships()
    .iter()
    .filter(r => r.owner == self.main)
    .map(r => (r.id, r))
    .to_array(),
  )
}
