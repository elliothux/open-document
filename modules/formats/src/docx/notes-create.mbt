///|
fn note_reference(node : @xml.Node) -> Bool {
  node.uri == word_uri &&
  ["footnoteReference", "endnoteReference"].contains(node.name)
}

///|
fn Session::next_note_key(
  self : Session,
  kind : String,
) -> String raise @failure.Failure {
  let used : Set[String] = Set([])
  if self.note_source(kind) is Some(source) {
    for id in source.tree.children[0] {
      used.add(
        @string.parse_int(
          source.tree.nodes[id]
          .attribute("id", uri=word_uri)
          .unwrap_or("")
          .trim(),
        ).to_string() catch {
          _ => @failure.reject("protected-content", "Invalid note identity")
        },
      )
    }
  }
  for part in self.style_part_names() {
    for node in self.part_xml(part).nodes() {
      if node.uri == word_uri && node.name == kind + "Reference" {
        used.add(note_key(node.attribute("id", uri=word_uri).unwrap_or("")))
      }
    }
  }
  for value in 1..<=8192 {
    if !used.contains(value.to_string()) {
      return value.to_string()
    }
  }
  @failure.reject("limit-exceeded", "Note identities exhausted")
}

///|
fn Session::append_note_source(
  self : Session,
  kind : String,
  key : String,
  body : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let view = { ..self, parts, }
  let source = view.note_source(kind)
  let part = source
    .map(source => source.part)
    .unwrap_or_else(() => view.new_word_part(kind + "s", parts, edits, created))
  let initial = parts.get(part).unwrap_or_else(() => view.part_xml(part))
  let separators = if source is None {
    [(-1, "separator"), (0, "continuationSeparator")]
    .map(pair => {
      "<od:\{kind} xmlns:od='\{word_uri}' od:id='\{pair.0}' od:type='\{pair.1}'><od:p><od:r><od:\{pair.1}/></od:r></od:p></od:\{kind}>"
    })
    .join("")
  } else {
    ""
  }
  let (story, step) = append_part_xml(
    initial,
    separators +
    "<od:\{kind} xmlns:od='\{word_uri}' od:id='\{key}'>\{body}</od:\{kind}>",
  )
  parts[part] = story
  if created.contains(part) {
    created[part] = story
  } else {
    edits.get_or_init(part, () => []).push(step)
  }
}

///|
fn Session::check_note_paragraph(
  self : Session,
  document : @xml.Document,
  paragraph : Int32,
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  guard tree.nodes.get(paragraph) is Some(node) &&
    node.parent >= 0 &&
    ["body", "tc"].contains(tree.nodes[node.parent].name) else {
    @failure.reject(
      "protected-content", "Notes require a body or ordinary table paragraph",
    )
  }
  let references = tree
    .descendants(paragraph)
    .filter(id => note_reference(tree.nodes[id]))
  let changes : Array[@xml.SourceChange] = references.map(id => {
    let node = tree.nodes[id]
    guard tree.nodes[node.parent].uri == word_uri &&
      tree.nodes[node.parent].name == "r" &&
      tree.nodes[node.parent].parent == paragraph &&
      tree.children[id].is_empty() &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => a.uri == word_uri && a.name == "id") else {
      @failure.reject(
        "protected-content", "Custom or nested note references are protected",
      )
    }
    ignore(note_key(node.attribute("id", uri=word_uri).unwrap_or("")))
    {
      node: paragraph,
      offset: node.start - tree.nodes[paragraph].start,
      length: node.end - node.start,
      xml: "",
    }
  })
  let clean = if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
  let position : Position = {
    paragraph,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  ignore(
    self.paragraph_range_in(
      clean,
      WordTree::new(clean),
      { anchor: position, focus: position, },
      structural=true,
      fields=true,
      math=true,
      sectionBoundary=true,
    ),
  )
}

///|
fn note_reference_properties(
  properties : String,
  budget : @archive.Budget,
) -> String raise @failure.Failure {
  let document = @xml.Document::parse(
    @utf8.encode("<od:r xmlns:od='\{word_uri}'>\{properties}</od:r>"),
    "",
    budget.xml_depth,
    budget.entry_bytes,
  )
  formatted_properties(
    WordTree::new(document),
    document,
    0,
    "rPr",
    CharacterFormat::new(vertAlign=Set("superscript")).properties(),
  )
}

///|
fn Session::commit_note_command(
  self : Session,
  document : @xml.Document,
  xml : Array[@xml.Edit],
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  after : Selection?,
  paragraphs : Array[Int32],
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  let view = { ..self, document: Some(document), parts, }
  let layout = @layout.paginate(probe, view.flow(), profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Note commands require supported document layout",
    )
  }
  let mut bytes = xml_part_edit_bytes(edits, created)
  for step in xml {
    let count = edit_bytes(step)
    guard count <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Note transaction exceeds history budget",
      )
    }
    bytes += count
  }
  self.commit_edit(
    {
      xml,
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after,
      paragraphs,
      bytes,
    },
    document,
    parts~,
  )
  self.edit_result(paragraphs)
}

///|
/// Adds a native note at the ordered end of the selection without replacing selected content.
pub fn Session::insert_note(
  self : Session,
  revision : Int32,
  kind : String,
  text : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  check_note_text(text)
  guard ["footnote", "endnote"].contains(kind) else {
    @failure.reject("invalid-operation", "Invalid note kind")
  }
  guard self.selection is Some(selection) else {
    @failure.reject(
      "invalid-position", "Select a note reference position first",
    )
  }
  let document = self.document()
  self.check_position_in(document, selection.anchor)
  self.check_position_in(document, selection.focus)
  let tree = WordTree::new(document)
  ignore(self.editable_page_section(tree))
  let position = if tree.nodes[selection.anchor.paragraph].start >
    tree.nodes[selection.focus.paragraph].start ||
    (
      selection.anchor.paragraph == selection.focus.paragraph &&
      selection.anchor.offset > selection.focus.offset
    ) {
    selection.anchor
  } else {
    selection.focus
  }
  self.check_note_paragraph(document, position.paragraph)
  let key = self.next_note_key(kind)
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let styles = self.styles([])
  let style = if kind == "footnote" { "FootnoteText" } else { "EndnoteText" }
  let ppr = if styles.ids.contains(style) {
    "<od:pPr><od:pStyle od:val='\{style}'/></od:pPr>"
  } else {
    "<od:pPr><od:spacing od:after='0' od:line='240' od:lineRule='auto'/></od:pPr>"
  }
  let size = if styles.ids.contains(style) {
    ""
  } else {
    "<od:sz od:val='20'/>"
  }
  let markup = text
    .split("\n")
    .to_array()
    .mapi((index, line) => {
      let marker = if index == 0 {
        "<od:r><od:rPr>\{size}<od:vertAlign od:val='superscript'/></od:rPr><od:\{kind}Ref/></od:r>"
      } else {
        ""
      }
      "<od:p>\{ppr}\{marker}<od:r><od:rPr>\{size}</od:rPr><od:t xml:space='preserve'>\{@xml.escape_text(line.to_owned())}</od:t></od:r></od:p>"
    })
    .join("")
  self.append_note_source(kind, key, markup, parts, edits, created)
  let change = self.paragraph_inline_source(document, position, properties => {
    "<od:r xmlns:od='\{word_uri}'>\{note_reference_properties(properties, self.opc.budget)}<od:\{kind}Reference od:id='\{key}'/></od:r>"
  })
  let (candidate, step) = document.edit_source([change])
  let caret = {
    ..position,
    offset: position.offset + 1,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  self.check_position_in(candidate, caret)
  self.commit_note_command(
    candidate,
    [step],
    parts,
    edits,
    created,
    Some({ anchor: caret, focus: caret, }),
    [position.paragraph],
    probe~,
    profile~,
    images~,
  )
}
