///|
fn fragment_paragraph_length(tree : WordTree, paragraph : Int) -> Int {
  docx_texts(tree)
  .filter(text => text.paragraph == paragraph)
  .fold(init=0, (sum, text) => sum + inline_text(tree.nodes[text.id]).length())
}

///|
/// Inserts portable paragraphs and tables using the existing range and resource transaction.
pub fn Session::paste_body_fragment(
  self : Session,
  revision : Int,
  selection : Selection,
  fragment : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let media = self.media.copy()
  let added : Map[String, Bytes] = Map([])
  let incoming = self.read_body_fragment(
    fragment, parts, part_edits, created, media, added,
  )
  let source = WordTree::new(incoming)
  let blocks = source.children[source.child(0, "body").unwrap()]
  let first_paragraph = source.nodes[blocks[0]].name == "p"
  let last_paragraph = source.nodes[blocks.last().unwrap()].name == "p"
  let first_properties = source
    .child(blocks[0], "pPr")
    .map(id => source.standalone_markup(incoming, id))
    .unwrap_or("")
  let original = self.document()
  let original_tree = WordTree::new(original)
  let range = self.paragraph_range(
    original_tree,
    selection,
    structural=true,
    fields=true,
    tables=true,
  )
  if blocks.any(id => source.nodes[id].name == "tbl") {
    guard original_tree.nodes[range.start.paragraph].parent ==
      original_tree.child(0, "body").unwrap() else {
      @failure.reject(
        "protected-content", "Nested table insertion requires support",
      )
    }
    ignore(self.editable_page_section(original_tree))
  }
  let table_at_start = !first_paragraph && range.start.offset == 0
  let carry_break = table_at_start &&
    self.flow_from(original).paragraphs
    .iter()
    .find_first(p => p.id == range.start.paragraph)
    .unwrap().pageBreakBefore
  let prepared = if table_at_start {
    self.prepare_plain_range(selection, "")
  } else {
    Some(self.prepare_structural_range_in(original, selection, "\n"))
  }
  let steps = prepared.map(p => p.edit.xml.copy()).unwrap_or([])
  let mut candidate = prepared.map(p => p.document).unwrap_or(original)
  let left = range.start.paragraph
  let right = prepared
    .bind(p => p.edit.after)
    .map(s => s.focus.paragraph)
    .unwrap_or(left)
  let tree = WordTree::new(candidate)
  let node = tree.nodes[right]
  let markup = blocks.map(p => source.standalone_markup(incoming, p)).join("")
  let (document, edit) = candidate.edit_source([
    {
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: 0,
      xml: markup,
    },
  ])
  candidate = document
  steps.push(edit)
  let tree = WordTree::new(candidate)
  let siblings = tree.children[tree.nodes[left].parent]
  let end = siblings.search(right).unwrap()
  let inserted = siblings[end - blocks.length():end].to_owned()
  guard inserted.length() == blocks.length() else {
    @failure.reject(
      "invalid-operation", "Rich insertion did not preserve paragraph boundaries",
    )
  }
  // Resolve the receiving prefix before applying the copied paragraph properties.
  let view = { ..self, document: Some(candidate), parts, media, }
  let styles = view.styles([])
  let changes = []
  if first_paragraph && blocks.length() > 1 {
    for run in tree.paragraph_runs(left, running=true) {
      if view.preserve_run_style(tree, styles, run, inserted[0]) is Some(change) {
        changes.push(change)
      }
    }
    if properties_change(tree, candidate, left, "pPr", first_properties)
      is Some(change) {
      changes.push(change)
    }
  }
  if !changes.is_empty() {
    let (document, edit) = candidate.edit_source(changes)
    candidate = document
    steps.push(edit)
  }
  if carry_break {
    let tree = WordTree::new(candidate)
    let first = tree
      .descendants(inserted[0])
      .iter()
      .find_first(id => {
        tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
      })
      .unwrap()
    for (paragraph, value) in [(first, true), (right, false)] {
      let position = table_position(paragraph)
      if self.format_paragraph_document(
          candidate,
          { anchor: position, focus: position, },
          ParagraphFormat::new(pageBreakBefore=Set(value)),
        )
        is Some((updated, edit)) {
        candidate = updated
        steps.push(edit)
      }
    }
  }
  let tree = WordTree::new(candidate)
  let position : Position = {
    paragraph: left,
    offset: fragment_paragraph_length(tree, left),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  if first_paragraph {
    let other = { ..position, paragraph: inserted[0], offset: 0, }
    let view = { ..self, document: Some(candidate), parts, media, }
    let merged = view.prepare_structural_range_in(
      candidate,
      { anchor: position, focus: other, },
      "",
    )
    candidate = merged.document
    steps.append(merged.edit.xml)
  }
  let mut focus = { ..position, paragraph: right, offset: 0, }
  if last_paragraph {
    let last = if inserted.length() == 1 {
      left
    } else {
      inserted.last().unwrap()
    }
    let tree = WordTree::new(candidate)
    let position = {
      ..position,
      paragraph: last,
      offset: fragment_paragraph_length(tree, last),
    }
    let other = { ..position, paragraph: right, offset: 0, }
    let view = { ..self, document: Some(candidate), parts, media, }
    let merged = view.prepare_structural_range_in(
      candidate,
      { anchor: position, focus: other, },
      "",
    )
    candidate = merged.document
    steps.append(merged.edit.xml)
    focus = merged.edit.after.unwrap().focus
  }
  let view = { ..self, document: Some(candidate), parts, media, }
  WordTree::new(candidate).check_drawing_budget()
  let flow = view.flow_from(candidate)
  let layout = @layout.paginate(
    probe,
    flow,
    profile,
    images.unwrap_or_else(() => @layout.Images::new()),
  )
  let tree = WordTree::new(candidate)
  let fields = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri &&
    tree.nodes[id].name == "fldSimple" &&
    !original_tree.nodes.contains(id)
  })
  let changes = self.field_cache_changes(tree, fields, layout)
  if !changes.is_empty() {
    let (document, edit) = candidate.edit_text(changes)
    candidate = document
    steps.push(edit)
  }
  let mut bytes = xml_part_edit_bytes(part_edits, created)
  for value in added.values() {
    guard value.length() <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Rich picture history exceeds budget")
    }
    bytes += value.length()
  }
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Rich text history exceeds budget")
    }
    bytes += size
  }
  let affected = range.paragraphs.copy()
  for id in inserted {
    if tree.nodes.contains(id) {
      affected.append(
        tree
        .descendants(id)
        .filter(child => {
          tree.nodes[child].uri == word_uri && tree.nodes[child].name == "p"
        }),
      )
    }
  }
  affected.push(right)
  let focus = { ..focus, affinity: "before", }
  self.commit_edit(
    {
      xml: steps,
      parts: part_edits,
      created,
      created_media: added,
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: affected,
      bytes,
    },
    candidate,
    parts~,
    media~,
  )
  self.edit_result(affected)
}
