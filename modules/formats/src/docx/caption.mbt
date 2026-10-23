///|
fn Session::caption_style(
  self : Session,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let styles = self.styles([])
  if styles.tree is Some(tree) {
    for key, id in styles.ids {
      if tree.nodes[id].attribute("type", uri=word_uri).unwrap_or("paragraph") ==
        "paragraph" &&
        (
          key == "Caption" ||
          tree.value(id, "name").unwrap_or("").to_lower() == "caption"
        ) {
        styles.validate_style(key, "paragraph")
        return key
      }
    }
  }
  guard styles.ids.length() < 4096 else {
    @failure.reject("limit-exceeded", "Too many styles for a caption")
  }
  let reserved : Set[String] = Set([])
  for part in self.style_part_names() {
    for node in self.part_xml(part).nodes() {
      if node.uri == word_uri &&
        style_reference_names.contains(node.name) &&
        node.attribute("val", uri=word_uri) is Some(key) {
        reserved.add(key)
      }
    }
  }
  let key = for i in 0..<=65536 {
    let key = if i == 0 { "Caption" } else { "odCaption\{i}" }
    if !styles.ids.contains(key) && !reserved.contains(key) {
      break key
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free caption style identity")
  }
  let base = styles.default_paragraph
    .map(key => {
      let key = property_attribute(key)
      "<od:basedOn od:val=\"\{key}\"/><od:next od:val=\"\{key}\"/>"
    })
    .unwrap_or("")
  let (paragraph, character) = builtin_style_properties(
    "Caption",
    "caption",
    "paragraph",
    styles.themes,
  ).unwrap()
  let markup = "<od:style xmlns:od=\"\{word_uri}\" od:type=\"paragraph\" od:styleId=\"\{key}\"><od:name od:val=\"caption\"/>\{base}\{paragraph}\{character}</od:style>"
  let part = if styles.tree is Some(_) {
    styles.part
  } else {
    self.new_word_part("styles", parts, edits, created)
  }
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let (candidate, edit) = append_part_xml(document, markup)
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  { ..self, parts, }.styles([]).validate_style(key, "paragraph")
  key
}

///|
/// Inserts an editable caption beside the current body paragraph or table.
pub fn Session::insert_caption(
  self : Session,
  revision : Int,
  label : String,
  text : String,
  before : Bool,
  format : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard label.length() <= 40 &&
    !label.contains(":") &&
    ["", "decimal", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman"].contains(
      format,
    ) &&
    text.length() <= 1024 &&
    [label, text].all(value => {
      @xml.valid_text(value) &&
      value
      .iter()
      .all(c => {
        c.to_int() >= 32 && c != '\u007f' && c != '\u2028' && c != '\u2029'
      })
    }) else {
    @failure.reject(
      "invalid-operation", "Caption requires a label and a single-line description of at most 1024 units",
    )
  }
  let instruction = running_field_instruction(
    "SEQ:" + label + (if format.is_empty() { "" } else { ":" + format }),
  )
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a caption position first")
  }
  let original = self.document()
  let tree = WordTree::new(original)
  ignore(self.editable_page_section(tree))
  tree.check_editable_paragraph(
    selection.focus.paragraph,
    part=self.main,
    pictures=true,
    fields=true,
    math=true,
  )
  let body = tree.child(0, "body").unwrap()
  let target = for id = selection.focus.paragraph
                   tree.nodes[id].parent != body
                   id = tree.nodes[id].parent {
    guard tree.nodes[id].parent >= 0 else {
      @failure.reject(
        "protected-content", "Caption requires a body paragraph or table",
      )
    }
  } nobreak {
    id
  }
  guard ["p", "tbl"].contains(tree.nodes[target].name) else {
    @failure.reject(
      "protected-content", "Caption requires a body paragraph or table",
    )
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let style = property_attribute(self.caption_style(parts, edits, created))
  let description = if text.is_empty() {
    ""
  } else {
    "<od:r><od:t xml:space=\"preserve\"> \{@xml.escape_text(text)}</od:t></od:r>"
  }
  let keep = if before { "<od:keepNext/>" } else { "" }
  let markup = "<od:p xmlns:od=\"\{word_uri}\"><od:pPr><od:pStyle od:val=\"\{style}\"/>\{keep}</od:pPr><od:r><od:t xml:space=\"preserve\">\{@xml.escape_text(label)} </od:t></od:r><od:fldSimple od:instr=\"\{property_attribute(instruction)}\" od:dirty=\"true\"><od:r><od:t>1</od:t></od:r></od:fldSimple>\{description}</od:p>"
  let (candidate, edit) = original.edit_source([
    {
      node: body,
      offset: (if before {
        tree.nodes[target].start
      } else {
        tree.nodes[target].end
      }) -
      tree.nodes[body].start,
      length: 0,
      xml: markup,
    },
  ])
  let steps = [edit]
  let updated = WordTree::new(candidate)
  let paragraph = updated.children[body]
    .iter()
    .find_first(id => updated.nodes[id].name == "p" && !tree.nodes.contains(id))
    .unwrap()
  let field = updated.child(paragraph, "fldSimple").unwrap()
  let layout = @layout.paginate(
    probe,
    { ..self, document: Some(candidate), parts, }.flow(),
    profile,
    images,
  )
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Caption insertion requires a complete layout",
    )
  }
  let (candidate, edit) = candidate.edit_text(
    self.field_cache_changes(updated, [field], layout),
  )
  steps.push(edit)
  let mut bytes = xml_part_edit_bytes(edits, created)
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Caption insertion history exceeds budget",
      )
    }
    bytes += size
  }
  let focus : Position = {
    paragraph,
    offset: label.length() +
    2 +
    (if text.is_empty() { 0 } else { text.length() + 1 }),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  self.check_position_in(candidate, focus)
  let paragraphs = [paragraph]
  self.commit_edit(
    {
      xml: steps,
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs,
      bytes,
    },
    candidate,
    parts~,
  )
  self.edit_result(paragraphs)
}
