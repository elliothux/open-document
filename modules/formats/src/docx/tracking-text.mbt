///|
priv struct ReviewTextPart {
  root : Int
  run : Int
  text : String
  kind : String
  author : String
}

///|
fn WordTree::review_text_parts(
  self : WordTree,
  paragraph : Int,
) -> Array[ReviewTextPart] raise @failure.Failure {
  guard self.nodes.get(paragraph) is Some(node) &&
    node.uri == word_uri &&
    node.name == "p" else {
    @failure.reject("invalid-position", "Unknown revision paragraph")
  }
  self.check_revision_paragraph(paragraph)
  guard node.attributes.all(a => {
      a.uri == word_uri &&
      ["rsidR", "rsidRDefault", "rsidP", "rsidRPr", "rsidDel"].contains(a.name)
    }) &&
    self.children[paragraph]
    .filter(id => self.nodes[id].uri == word_uri && self.nodes[id].name == "pPr")
    .length() <=
    1 else {
    @failure.reject(
      "protected-content", "Extended or duplicate paragraph properties prevent tracked editing",
    )
  }
  let source = self.source[node.start:node.end]
  guard node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown paragraph text prevents tracked editing",
    )
  }
  let parts : Array[ReviewTextPart] = []
  for root in self.children[paragraph] {
    let node = self.nodes[root]
    guard node.uri == word_uri else {
      @failure.reject(
        "protected-content", "Foreign paragraph content requires tracked editing support",
      )
    }
    if node.name == "pPr" {
      self.check_review_properties(root)
      continue
    }
    let kind = node.name
    guard ["r", "ins", "del"].contains(kind) else {
      @failure.reject(
        "protected-content", "This paragraph content requires tracked editing support",
      )
    }
    if kind != "r" {
      ignore(self.check_text_revision(root))
    }
    for run in (if kind == "r" { [root] } else { self.children[root] }) {
      let node = self.nodes[run]
      guard node.uri == word_uri &&
        node.name == "r" &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => {
          a.uri == word_uri && ["rsidR", "rsidDel", "rsidRPr"].contains(a.name)
        }) else {
        @failure.reject(
          "protected-content", "Extended run source prevents tracked editing",
        )
      }
      let text = StringBuilder()
      let properties = self.children[run].filter(id => {
        self.nodes[id].uri == word_uri && self.nodes[id].name == "rPr"
      })
      guard properties.length() <= 1 else {
        @failure.reject(
          "protected-content", "Duplicate run properties prevent tracked editing",
        )
      }
      for child in self.children[run] {
        let content = self.nodes[child]
        guard content.uri == word_uri else {
          @failure.reject(
            "protected-content", "Foreign run content prevents tracked editing",
          )
        }
        if content.name == "rPr" {
          self.check_review_properties(child)
        } else if content.name == (if kind == "del" { "delText" } else { "t" }) {
          self.check_field_text(child)
          text.write_string(content.text)
        } else {
          guard ["tab", "cr", "br"].contains(content.name) &&
            self.children[child].is_empty() &&
            content.text.is_empty() &&
            content.attributes.all(a => {
              content.name == "br" &&
              a.uri == word_uri &&
              a.name == "type" &&
              a.value == "textWrapping"
            }) else {
            @failure.reject(
              "protected-content", "Structural or extended run content prevents tracked editing",
            )
          }
          text.write_string(inline_text(content))
        }
      }
      let source = self.source[node.start:node.end]
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Opaque run source prevents tracked editing",
        )
      }
      parts.push({
        root,
        run,
        text: text.to_string(),
        kind,
        author: self.nodes[root].attribute("author", uri=word_uri).unwrap_or(""),
      })
    }
  }
  parts
}

///|
fn review_inline_markup(
  text : String,
  deleted : Bool,
) -> String raise @failure.Failure {
  let output = StringBuilder()
  let chunk = StringBuilder()
  fn flush() raise @failure.Failure {
    if !chunk.to_string().is_empty() {
      let tag = if deleted { "delText" } else { "t" }
      output.write_string(
        "<od:\{tag} xml:space=\"preserve\">" +
        @xml.escape_text(chunk.to_string()) +
        "</od:\{tag}>",
      )
      chunk.reset()
    }
  }
  for ch in text {
    match ch {
      '\t' => {
        flush()
        output.write_string("<od:tab/>")
      }
      '\u2028' => {
        flush()
        output.write_string("<od:br/>")
      }
      _ => chunk.write_char(ch)
    }
  }
  flush()
  output.to_string()
}

///|
fn WordTree::review_run_markup(
  self : WordTree,
  document : @xml.Document,
  run : Int?,
  text : String,
  deleted : Bool,
  patch? : CharacterFormat,
  paragraph? : Int,
) -> String raise @failure.Failure {
  if text.is_empty() {
    return ""
  }
  let attributes = StringBuilder()
  if run is Some(run) {
    for attribute in self.nodes[run].attributes {
      attributes.write_string(
        " od:\{attribute.name}=\"" + property_attribute(attribute.value) + "\"",
      )
    }
  }
  let property_parent = match run {
    Some(_) => run
    None => paragraph.bind(id => self.child(id, "pPr"))
  }
  let properties = if property_parent is Some(parent) &&
    (patch is Some(_) || run is None) {
    formatted_properties(
      self,
      document,
      parent,
      "rPr",
      patch.unwrap_or(CharacterFormat::new()).properties(),
      nested=if run is None { { "rPrChange": "" } } else { Map([]) },
    )
  } else if patch is Some(patch) {
    "<od:rPr xmlns:od=\"\{word_uri}\">" +
    character_properties_markup(patch) +
    "</od:rPr>"
  } else {
    run
    .bind(run => self.child(run, "rPr"))
    .map(id => self.standalone_markup(document, id))
    .unwrap_or("")
  }
  "<od:r xmlns:od=\"\{word_uri}\"\{attributes.to_string()}>" +
  properties +
  review_inline_markup(text, deleted) +
  "</od:r>"
}

///|
fn WordTree::review_part_markup(
  self : WordTree,
  document : @xml.Document,
  part : ReviewTextPart,
  from : Int,
  to : Int,
) -> String raise @failure.Failure {
  if from >= to {
    return ""
  }
  let run = self.nodes[part.run]
  let content = if from == 0 && to == part.text.length() {
    self.standalone_markup(document, run.id)
  } else {
    self.review_run_markup(
      document,
      Some(run.id),
      part.text[from:to].to_owned(),
      part.kind == "del",
    )
  }
  if part.kind == "r" {
    return content
  }
  let node = self.nodes[part.root]
  self.source[node.start:node.opening_end].to_owned() +
  content +
  "</" +
  node.qualified +
  ">"
}

///|
fn revision_author(
  author : String,
  date : String,
) -> Unit raise @failure.Failure {
  guard !author.trim().is_empty() &&
    author.length() <= 255 &&
    @xml.valid_text(author) &&
    !author.iter().any(ch => ch < ' ') else {
    @failure.reject(
      "invalid-operation", "Tracked changes require an explicit bounded author",
    )
  }
  check_comment_date(date)
}

///|
fn WordTree::unused_revision_id(
  self : WordTree,
  reserved : Int?,
) -> Int raise @failure.Failure {
  let used : Set[String] = Set([])
  for node in self.nodes.values() {
    if node.uri == word_uri && revision_element(node.name) {
      if node.attribute("id", uri=word_uri) is Some(id) {
        used.add(id)
      }
    }
  }
  for id in 0..<16384 {
    if reserved != Some(id) && !used.contains(id.to_string()) {
      return id
    }
  }
  @failure.reject("limit-exceeded", "Revision identities exhausted")
}

///|
fn review_wrapper(
  id : Int,
  author : String,
  date : String,
  deleted : Bool,
  markup : String,
) -> String raise @failure.Failure {
  if markup.is_empty() {
    return ""
  }
  let name = if deleted { "del" } else { "ins" }
  "<od:\{name} xmlns:od=\"\{word_uri}\" od:id=\"\{id}\" od:author=\"" +
  property_attribute(author) +
  "\" od:date=\"" +
  property_attribute(date) +
  "\">" +
  markup +
  "</od:\{name}>"
}

///|
fn Session::prepare_review_text(
  self : Session,
  selection : Selection,
  text : String,
  author : String,
  date : String,
  track~ : Bool = true,
) -> PreparedEdit? raise @failure.Failure {
  if track {
    revision_author(author, date)
  }
  self.check_document_protection()
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Tracked input exceeds UTF-16 budget")
  }
  guard valid_inline_input(text) &&
    !text.contains("\n") &&
    !has_region_break(text) &&
    selection.anchor.paragraph == selection.focus.paragraph else {
    @failure.reject(
      "protected-content", "Tracked paragraph boundaries require structural revision support",
    )
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let paragraph = selection.anchor.paragraph
  let parts = tree.review_text_parts(paragraph)
  let content = parts.map(part => part.text).join("")
  let boundaries = editing_boundaries(content, true)
  validate_position(selection.anchor, boundaries)
  validate_position(selection.focus, boundaries)
  let start = selection.anchor.offset.min(selection.focus.offset)
  let end = selection.anchor.offset.max(selection.focus.offset)
  if content[start:end] == text {
    return None
  }
  if track &&
    self.typing_format is None &&
    start == end &&
    !text.is_empty() &&
    self.selection == Some(selection) &&
    selection.anchor.affinity == "after" {
    for part in parts; cursor = 0 {
      let length = part.text.length()
      if part.kind == "ins" &&
        part.author == author &&
        start >= cursor &&
        start <= cursor + length {
        let offset = start - cursor
        let updated = part.text[:offset].to_owned() +
          text +
          part.text[offset:].to_owned()
        let markup = tree.review_run_markup(
          document,
          Some(part.run),
          updated,
          false,
        )
        let node = tree.nodes[part.run]
        let parent = tree.nodes[node.parent]
        let (candidate, step) = document.edit_source([
          {
            node: parent.id,
            offset: node.start - parent.start,
            length: node.end - node.start,
            xml: markup,
          },
        ])
        let updated = content[:start].to_owned() +
          text +
          content[start:].to_owned()
        let caret = @layout.grapheme_boundaries(updated)
          .iter()
          .find_first(value => value >= start + text.length())
          .unwrap()
        let position = {
          ..selection.anchor,
          offset: caret,
          affinity: "after",
          bidiLevel: None,
          frameStart: None,
        }
        return Some({
          document: candidate,
          typing_text: None,
          join_group: true,
          edit: {
            xml: [step],
            parts: Map([]),
            created: Map([]),
            created_media: Map([]),
            before: self.selection,
            after: Some({ anchor: position, focus: position, }),
            paragraphs: [paragraph],
            bytes: edit_bytes(step),
          },
        })
      }
      continue cursor + length
    }
  }
  if text.is_empty() {
    let mut selected = false
    let mut only_deleted = true
    for part in parts; cursor = 0 {
      let length = part.text.length()
      if start < cursor + length && end > cursor {
        selected = true
        only_deleted = only_deleted && part.kind == "del"
      }
      continue cursor + length
    }
    if selected && only_deleted {
      let position = {
        ..selection.focus,
        offset: if selection.anchor.offset > selection.focus.offset {
          start
        } else {
          end
        },
        affinity: "after",
        bidiLevel: None,
        frameStart: None,
      }
      return Some({
        document,
        typing_text: None,
        join_group: false,
        edit: {
          xml: [],
          parts: Map([]),
          created: Map([]),
          created_media: Map([]),
          before: self.selection,
          after: Some({ anchor: position, focus: position, }),
          paragraphs: [],
          bytes: 0,
        },
      })
    }
  }
  let prefix = StringBuilder()
  let retained = StringBuilder()
  let suffix = StringBuilder()
  let retained_text = StringBuilder()
  let deletion = if track { tree.unused_revision_id(None) } else { 0 }
  let insertion = if track {
    tree.unused_revision_id(Some(deletion))
  } else {
    0
  }
  let mut inherited : Int? = None
  let mut cursor = 0
  for part in parts {
    let length = part.text.length()
    if inherited is None && start <= cursor + length {
      inherited = Some(part.run)
    }
    let left = (start - cursor).clamp(min=0, max=length)
    let right = (end - cursor).clamp(min=0, max=length)
    if length == 0 {
      let raw = tree.standalone_markup(document, part.run)
      if cursor <= start {
        prefix.write_string(raw)
      } else {
        suffix.write_string(raw)
      }
    }
    prefix.write_string(tree.review_part_markup(document, part, 0, left))
    suffix.write_string(tree.review_part_markup(document, part, right, length))
    if right > left {
      if part.kind == "del" {
        retained.write_string(
          tree.review_part_markup(document, part, left, right),
        )
        retained_text.write_string(part.text[left:right].to_owned())
      } else if part.kind == "ins" {
        guard !track || part.author == author else {
          @failure.reject(
            "protected-content", "Deleting another author's insertion requires revision provenance support",
          )
        }
      } else if track {
        let value = part.text[left:right].to_owned()
        retained.write_string(
          review_wrapper(
            deletion,
            author,
            date,
            true,
            tree.review_run_markup(document, Some(part.run), value, true),
          ),
        )
        retained_text.write_string(value)
      }
    }
    cursor += length
  }
  let properties = tree
    .child(paragraph, "pPr")
    .map(id => tree.standalone_markup(document, id))
    .unwrap_or("")
  let pending = if start == end && self.selection == Some(selection) {
    self.typing_format
  } else {
    None
  }
  let added = tree.review_run_markup(
    document,
    inherited,
    text,
    false,
    patch?=pending,
    paragraph~,
  )
  let markup = properties +
    prefix.to_string() +
    retained.to_string() +
    (if track {
      review_wrapper(insertion, author, date, false, added)
    } else {
      added
    }) +
    suffix.to_string()
  guard markup.length() <=
    self.opc.budget.entry_bytes.min(history_byte_limit / 2) else {
    @failure.reject("limit-exceeded", "Tracked source exceeds paragraph budget")
  }
  let node = tree.nodes[paragraph]
  let change : @xml.SourceChange = if node.empty {
    {
      node: paragraph,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">" + markup + "</" + node.qualified + ">",
    }
  } else {
    {
      node: paragraph,
      offset: node.opening_end - node.start,
      length: node.closing_start - node.opening_end,
      xml: markup,
    }
  }
  let (candidate, step) = document.edit_source([change])
  let updated = content[:start].to_owned() +
    retained_text.to_string() +
    text +
    content[end:].to_owned()
  let offset = if text.is_empty() &&
    selection.anchor.offset > selection.focus.offset {
    start
  } else {
    start + retained_text.to_string().length() + text.length()
  }
  let caret = @layout.grapheme_boundaries(updated)
    .iter()
    .find_first(value => value >= offset)
    .unwrap()
  let position = {
    ..selection.anchor,
    offset: caret,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  ignore(WordTree::new(candidate).revision_entries())
  Some({
    document: candidate,
    typing_text: None,
    join_group: start == end &&
    self.selection == Some(selection) &&
    !text.is_empty(),
    edit: {
      xml: [step],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs: [paragraph],
      bytes: edit_bytes(step),
    },
  })
}

///|
/// Replaces a single body or ordinary cell range with native text revisions.
/// Existing deletions remain visible; deleting the author's own insertion removes it.
pub fn Session::replace_tracked_text(
  self : Session,
  revision : Int,
  selection : Selection,
  text : String,
  author : String,
  date : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let prepared = self.prepare_review_text(selection, text, author, date)
  if prepared is Some(prepared) {
    if prepared.edit.bytes == 0 {
      self.selection = prepared.edit.after
    } else {
      self.commit_edit(prepared.edit, prepared.document, tracking_edit=true)
    }
  }
  self.edit_result(prepared.map(value => value.edit.paragraphs).unwrap_or([]))
}
