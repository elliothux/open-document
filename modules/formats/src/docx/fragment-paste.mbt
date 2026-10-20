///|
fn fragment_paragraph_length(tree : WordTree, paragraph : Int) -> Int {
  docx_texts(tree)
  .filter(text => text.paragraph == paragraph)
  .fold(init=0, (sum, text) => sum + inline_text(tree.nodes[text.id]).length())
}

///|
/// Inserts portable paragraphs using the existing range and resource transaction.
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
  let paragraphs = source.children[source.child(0, "body").unwrap()]
  let first_properties = source
    .child(paragraphs[0], "pPr")
    .map(id => source.standalone_markup(incoming, id))
    .unwrap_or("")
  let original = self.document()
  let original_tree = WordTree::new(original)
  let range = self.paragraph_range(original_tree, selection, structural=true)
  let prepared = self.prepare_structural_range_in(original, selection, "\n")
  let steps = prepared.edit.xml.copy()
  let mut candidate = prepared.document
  let left = range.start.paragraph
  let right = prepared.edit.after.unwrap().focus.paragraph
  let tree = WordTree::new(candidate)
  let node = tree.nodes[right]
  let markup = paragraphs
    .map(p => source.standalone_markup(incoming, p))
    .join("")
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
  let inserted = siblings[siblings.search(left).unwrap() + 1:siblings
  .search(right)
  .unwrap()].to_owned()
  guard inserted.length() == paragraphs.length() else {
    @failure.reject(
      "invalid-operation", "Rich insertion did not preserve paragraph boundaries",
    )
  }
  // Resolve the receiving prefix before applying the copied paragraph properties.
  let view = { ..self, document: Some(candidate), parts, media, }
  let styles = view.styles([])
  let changes = []
  if paragraphs.length() > 1 {
    for run in tree.paragraph_runs(left) {
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
  let tree = WordTree::new(candidate)
  let position : Position = {
    paragraph: left,
    offset: fragment_paragraph_length(tree, left),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let other = { ..position, paragraph: inserted[0], offset: 0, }
  let view = { ..self, document: Some(candidate), parts, media, }
  let merged = view.prepare_structural_range_in(
    candidate,
    { anchor: position, focus: other, },
    "",
  )
  candidate = merged.document
  steps.append(merged.edit.xml)
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
  let view = { ..self, document: Some(candidate), parts, media, }
  let flow = view.flow_from(candidate)
  ignore(
    @layout.paginate(
      probe,
      flow,
      profile,
      images.unwrap_or_else(() => @layout.Images::new()),
    ),
  )
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
  affected.append(inserted)
  let focus = { ..merged.edit.after.unwrap().focus, affinity: "before", }
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
