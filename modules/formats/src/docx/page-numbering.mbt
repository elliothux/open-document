///|
/// Native numbering settings; an absent start continues the preceding section.
pub(all) struct SectionNumbering {
  start : Int64?
  format : String
}

///|
pub impl ToJson for SectionNumbering with fn to_json(self) {
  let start : Json = match self.start {
    Some(value) => Json::number(value.to_double())
    None => Json::null()
  }
  { "start": start, "format": self.format }
}

///|
pub extend SectionNumbering with ToJson::{to_json}

///|
fn WordTree::section_numbering(
  self : WordTree,
  section : Int?,
) -> SectionNumbering raise @failure.Failure {
  let default : SectionNumbering = { start: None, format: "decimal", }
  guard section is Some(section) else { return default }
  let nodes = self.children[section].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == "pgNumType"
  })
  guard nodes.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate page numbering")
  }
  guard nodes is [id] else { return default }
  let node = self.nodes[id]
  let markup = self.source[node.start:node.end]
  guard !markup.contains("<!--") && !markup.contains("<?") else {
    @failure.reject(
      "protected-content", "Annotated page numbering is protected",
    )
  }
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["start", "fmt"].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Extended page numbering requires section support",
    )
  }
  let start = node
    .attribute("start", uri=word_uri)
    .map(start => {
      guard !start.is_empty() && start.iter().all(c => c >= '0' && c <= '9') else {
        @failure.reject("protected-content", "Invalid page numbering start")
      }
      @string.parse_int64(start[:]) catch {
        _ =>
          @failure.reject("protected-content", "Invalid page numbering start")
      }
    })
  let value : SectionNumbering = {
    start,
    format: node.attribute("fmt", uri=word_uri).unwrap_or("decimal"),
  }
  @layout.PageNumbering::{ start: start.unwrap_or(1L), format: value.format, }.validate()
  value
}

///|
fn WordTree::page_numbering(
  self : WordTree,
  section : Int?,
) -> @layout.PageNumbering raise @failure.Failure {
  let value = self.section_numbering(section)
  { start: value.start.unwrap_or(1L), format: value.format, }
}

///|
fn Session::page_numbering_query(
  self : Session,
  tree : WordTree,
  index : Int,
) -> Json {
  try {
    let section = self.editable_page_section(tree, target=Some(index))
    { "value": tree.section_numbering(section), "reason": "" }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
/// Changes one section's page numbering and preflights layout in one source transaction.
pub fn Session::set_page_numbering(
  self : Session,
  revision : Int,
  sectionIndex : Int,
  value : SectionNumbering?,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if value is Some(value) {
    @layout.PageNumbering::{
      start: value.start.unwrap_or(1L),
      format: value.format,
    }.validate()
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree, target=Some(sectionIndex))
  let current = tree.section_numbering(section)
  if value is Some(value) &&
    value.start == current.start &&
    value.format == current.format {
    return self.edit_state()
  }
  if value is None && section.bind(id => tree.child(id, "pgNumType")) is None {
    return self.edit_state()
  }
  let (candidate, edits, section) = page_section(original, tree, section)
  let tree = WordTree::new(candidate)
  let markup = value
    .map(value => {
      let start = value.start
        .map(start => " w:start=\"\{start}\"")
        .unwrap_or("")
      "<w:pgNumType xmlns:w=\"\{word_uri}\" w:fmt=\"\{value.format}\"\{start}/>"
    })
    .unwrap_or("")
  let change : @xml.SourceChange? = if value is Some(_) &&
    tree.child(section, "pgNumType") is None &&
    !tree.nodes[section].empty {
    let previous = tree.children[section]
      .filter(id => {
        [
          "headerReference", "footerReference", "footnotePr", "endnotePr", "type",
          "pgSz", "pgMar", "paperSrc", "pgBorders", "lnNumType",
        ].contains(tree.nodes[id].name)
      })
      .last()
    Some({
      node: section,
      offset: previous
      .map(id => tree.nodes[id].end)
      .unwrap_or(tree.nodes[section].opening_end) -
      tree.nodes[section].start,
      length: 0,
      xml: markup,
    })
  } else {
    properties_change(tree, candidate, section, "pgNumType", markup)
  }
  guard change is Some(change) else { return self.edit_state() }
  let (candidate, edit) = candidate.edit_source([change])
  edits.push(edit)
  self.commit_running(
    candidate,
    edits,
    self.parts.copy(),
    Map([]),
    Map([]),
    probe~,
    profile~,
    images~,
  )
}
