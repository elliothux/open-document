///|
fn citation_code(instruction : String) -> String raise @failure.Failure {
  let tokens = text_reference_tokens(instruction)
  guard tokens is [(command, false), (tag, _), ..] &&
    command.to_upper() == "CITATION" else {
    @failure.reject("protected-content", "Expected a citation source tag")
  }
  check_source_tag(tag)
  guard tokens.length() == 2 ||
    (
      tokens.length() == 4 &&
      tokens[2] == ("\\*", false) &&
      tokens[3].0.to_upper() == "MERGEFORMAT" &&
      !tokens[3].1
    ) else {
    @failure.reject(
      "protected-content", "Citation switches require formatting support",
    )
  }
  "CITATION:" + tag
}

///|
fn Session::citation_text(
  self : Session,
  tag : String,
) -> String raise @failure.Failure {
  check_source_tag(tag)
  guard self.bibliography_part() is Some((_, document)) else {
    @failure.reject("invalid-operation", "Select an available document source")
  }
  let records = read_bibliography_sources(WordTree::new(document))
  guard records.iter().find_first(record => record.value.tag == tag)
    is Some(record) &&
    record.reason.is_empty() &&
    record.author_reason.is_empty() else {
    @failure.reject(
      "protected-content", "Citation requires a supported source and author",
    )
  }
  let value = record.value
  let author = if value.author.is_empty() { value.title } else { value.author }
  guard !author.is_empty() else {
    @failure.reject("invalid-operation", "Citation requires an author or title")
  }
  "(" +
  author +
  (if value.year.is_empty() { "" } else { ", " + value.year }) +
  ")"
}

///|
/// Inserts one native citation with an author/year cache at the current range.
pub fn Session::insert_citation(
  self : Session,
  revision : Int32,
  tag : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.insert_body_page_field(
    revision,
    "CITATION:" + tag,
    probe~,
    profile~,
    images~,
  )
}

///|
/// Explicitly refreshes supported body citations using the basic author/year display.
pub fn Session::update_citations(
  self : Session,
  revision : Int32,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  ignore(self.editable_page_section(tree))
  let flow = self.flow()
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  let changes : Map[Int32, String] = Map([])
  let values : Map[String, String] = Map([])
  let affected : Array[Int32] = []
  for p in paragraphs {
    let cache : Map[Int32, String] = Map([])
    for id, code in tree.running_fields(p.id, cache~) {
      if !cache.contains(id) {
        continue
      }
      let value = if code.is_empty() {
        ""
      } else {
        let tag = code[9:].to_owned()
        match values.get(tag) {
          Some(value) => value
          None => {
            let value = self.citation_text(tag)
            values[tag] = value
            value
          }
        }
      }
      if tree.nodes[id].text != value {
        changes[id] = value
        if !affected.contains(p.id) {
          affected.push(p.id)
        }
      }
    }
  }
  if changes.is_empty() {
    return self.edit_state()
  }
  let (candidate, step) = original.edit_text(changes)
  let layout = @layout.paginate(
    probe,
    { ..self, document: Some(candidate), }.flow(),
    profile,
    images,
  )
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Citation update requires a complete layout",
    )
  }
  let typing = self.typing_format
  self.commit_edit(
    {
      xml: [step],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: affected,
      bytes: edit_bytes(step),
    },
    candidate,
  )
  self.typing_format = typing
  self.edit_result(affected)
}
