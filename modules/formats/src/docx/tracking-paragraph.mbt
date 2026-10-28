///|
fn review_paragraph_markup(
  id : Int32,
  author : String,
  date : String,
  deleted : Bool,
) -> String raise @failure.Failure {
  "<od:\{if deleted { "del" } else { "ins" }} xmlns:od=\"\{word_uri}\" od:id=\"\{id}\" od:author=\"\{property_attribute(author)}\" od:date=\"\{property_attribute(date)}\"/>"
}

///|
fn append_review_edit(
  before : PreparedEdit,
  next : PreparedEdit,
) -> PreparedEdit raise @failure.Failure {
  guard next.edit.bytes <= history_byte_limit - before.edit.bytes else {
    @failure.reject(
      "limit-exceeded", "Tracked paragraph history exceeds budget",
    )
  }
  let affected = before.edit.paragraphs.copy()
  for paragraph in next.edit.paragraphs {
    if !affected.contains(paragraph) {
      affected.push(paragraph)
    }
  }
  {
    ..next,
    join_group: false,
    edit: {
      ..next.edit,
      xml: before.edit.xml + next.edit.xml,
      before: before.edit.before,
      paragraphs: affected,
      bytes: before.edit.bytes + next.edit.bytes,
    },
  }
}

///|
fn Session::review_text_view(
  self : Session,
  prepared : PreparedEdit,
) -> Session {
  {
    ..self,
    document: Some(prepared.document),
    selection: prepared.edit.after,
    texts: docx_texts(WordTree::new(prepared.document)),
    typing_text: None,
    input_group: None,
  }
}

///|
fn Session::split_review_paragraph(
  self : Session,
  position : Position,
  author : String,
  date : String,
  track : Bool,
) -> PreparedEdit raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let parts = tree.review_text_parts(position.paragraph)
  let content = parts.map(part => part.text).join("")
  validate_position(position, editing_boundaries(content, true))
  let node = tree.nodes[position.paragraph]
  let before = StringBuilder()
  let after = StringBuilder()
  let mut units = 0
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let mut inherited : Int32? = None
  for part in parts; cursor = 0 {
    let length = part.text.length()
    if inherited is None && position.offset <= cursor + length {
      inherited = Some(part.run)
    }
    let offset = (position.offset - cursor).clamp(min=0, max=length)
    let left = tree.review_part_markup(document, part, 0, offset)
    let right = tree.review_part_markup(document, part, offset, length)
    guard left.length() + right.length() <= limit - units else {
      @failure.reject(
        "limit-exceeded", "Tracked paragraph source exceeds budget",
      )
    }
    units += left.length() + right.length()
    before.write_string(left)
    after.write_string(right)
    continue cursor + length
  }
  let marker = if track {
    review_paragraph_markup(tree.unused_revision_id(None), author, date, false)
  } else {
    ""
  }
  let run = inherited.unwrap_or_else(() => {
    tree.child(position.paragraph, "pPr").unwrap_or(position.paragraph)
  })
  let run_properties = formatted_properties(
    tree,
    document,
    run,
    "rPr",
    Map([]),
    nested={ "rPrChange": "", "ins": "", "del": "" },
  )
  if after.is_empty() {
    after.write_string(
      "<od:r xmlns:od=\"\{word_uri}\">\{run_properties}</od:r>",
    )
  }
  let end_properties = formatted_properties(
    tree,
    document,
    run,
    "rPr",
    Map([]),
    nested={ "rPrChange": "", "ins": marker, "del": "" },
  )
  let left_properties = formatted_properties(
    tree,
    document,
    position.paragraph,
    "pPr",
    Map([]),
    nested={ "rPr": end_properties },
  )
  let right_properties = tree
    .child(position.paragraph, "pPr")
    .map(id => tree.standalone_markup(document, id))
    .unwrap_or("")
  let markup = left_properties +
    before.to_string() +
    "</\{node.qualified}>" +
    structure_opening(node) +
    right_properties +
    after.to_string() +
    "</\{node.qualified}>"
  guard markup.length() <= limit else {
    @failure.reject("limit-exceeded", "Tracked paragraph source exceeds budget")
  }
  let (candidate, step) = document.edit_source([
    {
      node: node.parent,
      offset: node.opening_end -
      tree.nodes[node.parent].start -
      (if node.empty { 2 } else { 0 }),
      length: node.end - node.opening_end + (if node.empty { 2 } else { 0 }),
      xml: (if node.empty { ">" } else { "" }) + markup,
    },
  ])
  let updated = WordTree::new(candidate)
  let siblings = updated.children[node.parent]
  let next = siblings[siblings.search(node.id).unwrap() + 1]
  ignore(updated.review_text_parts(node.id))
  ignore(updated.review_text_parts(next))
  let focus : Position = {
    paragraph: next,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  {
    document: candidate,
    typing_text: None,
    join_group: false,
    edit: {
      xml: [step],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: [node.id, next],
      bytes: edit_bytes(step),
    },
  }
}

///|
fn Session::delete_review_boundary(
  self : Session,
  first : Int32,
  author : String,
  date : String,
  track : Bool,
) -> (PreparedEdit, Int32?) raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let last = tree.revision_next_paragraph(first)
  let length = tree
    .review_text_parts(first)
    .fold(init=0, (sum, part) => sum + part.text.length())
  ignore(tree.review_text_parts(last))
  let existing = tree.paragraph_revision(first)
  let merge = if existing is Some(id) {
    let mark = tree.nodes[id]
    if mark.name == "ins" {
      guard !track || mark.attribute("author", uri=word_uri) == Some(author) else {
        @failure.reject(
          "protected-content", "Review another author's inserted paragraph before deleting it",
        )
      }
      true
    } else {
      false
    }
  } else {
    !track
  }
  let (candidate, edits, removed) = if merge {
    let (candidate, edit, removed) = self.merge_review_paragraphs(
      document, first,
    )
    (candidate, [edit], Some(removed))
  } else if existing is None {
    let marker = review_paragraph_markup(
      tree.unused_revision_id(None),
      author,
      date,
      true,
    )
    let properties = paragraph_revision_properties(
      tree, document, first, marker,
    )
    let change = properties_change(tree, document, first, "pPr", properties).unwrap()
    let (candidate, edit) = document.edit_source([change])
    (candidate, [edit], None)
  } else {
    (document, [], None)
  }
  let focus : Position = {
    paragraph: first,
    offset: length,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  (
    {
      document: candidate,
      typing_text: None,
      join_group: false,
      edit: {
        xml: edits,
        parts: Map([]),
        created: Map([]),
        created_media: Map([]),
        before: self.selection,
        after: Some({ anchor: focus, focus, }),
        paragraphs: [first, last],
        bytes: edits.fold(init=0, (sum, edit) => sum + edit_bytes(edit)),
      },
    },
    removed,
  )
}

///|
fn Session::prepare_review_range(
  self : Session,
  selection : Selection,
  text : String,
  author : String,
  date : String,
  track~ : Bool = true,
) -> PreparedEdit? raise @failure.Failure {
  if selection.anchor.paragraph == selection.focus.paragraph &&
    !text.contains("\n") {
    return self.prepare_review_text(selection, text, author, date, track~)
  }
  if track {
    revision_author(author, date)
  }
  self.check_document_protection()
  guard text.length() <= command_limit &&
    valid_inline_input(text) &&
    !has_region_break(text) else {
    @failure.reject(
      "protected-content", "Tracked input requires bounded ordinary paragraph text",
    )
  }
  guard text.split("\n").count() <= 512 else {
    @failure.reject("limit-exceeded", "Tracked input exceeds paragraph budget")
  }
  let document = self.document()
  let tree = WordTree::new(document)
  guard tree.nodes.get(selection.anchor.paragraph) is Some(anchor) &&
    tree.nodes.get(selection.focus.paragraph) is Some(focus) &&
    anchor.parent == focus.parent else {
    @failure.reject(
      "protected-content", "Tracked input crosses a content region",
    )
  }
  let siblings = tree.children[anchor.parent]
  let a = siblings.search(anchor.id).unwrap()
  let b = siblings.search(focus.id).unwrap()
  let start = if a < b ||
    (a == b && selection.anchor.offset <= selection.focus.offset) {
    selection.anchor
  } else {
    selection.focus
  }
  let end = if start == selection.anchor {
    selection.focus
  } else {
    selection.anchor
  }
  let paragraphs = siblings[a.min(b):a.max(b) + 1].to_owned()
  guard paragraphs.length() <= 512 else {
    @failure.reject("limit-exceeded", "Tracked input exceeds paragraph budget")
  }
  for paragraph in paragraphs {
    ignore(tree.review_text_parts(paragraph))
  }
  validate_position(
    start,
    editing_boundaries(
      tree.review_text_parts(start.paragraph).map(part => part.text).join(""),
      true,
    ),
  )
  validate_position(
    end,
    editing_boundaries(
      tree.review_text_parts(end.paragraph).map(part => part.text).join(""),
      true,
    ),
  )
  let mut prepared : PreparedEdit = {
    document,
    typing_text: None,
    join_group: false,
    edit: {
      xml: [],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: start, focus: start, }),
      paragraphs: [],
      bytes: 0,
    },
  }
  let mut insertion = end
  for paragraph in paragraphs.rev() {
    let view = self.review_text_view(prepared)
    let content = WordTree::new(prepared.document)
      .review_text_parts(paragraph)
      .map(part => part.text)
      .join("")
    let from = {
      ..start,
      paragraph,
      offset: if paragraph == start.paragraph {
        start.offset
      } else {
        0
      },
    }
    let to = {
      ..end,
      paragraph,
      offset: if paragraph == end.paragraph {
        end.offset
      } else {
        content.length()
      },
    }
    if view.prepare_review_text(
        { anchor: from, focus: to, },
        "",
        author,
        date,
        track~,
      )
      is Some(next) {
      if paragraph == end.paragraph {
        insertion = next.edit.after.unwrap().focus
      }
      prepared = append_review_edit(prepared, next)
    }
  }
  for paragraph in paragraphs[:paragraphs.length() - 1].rev() {
    let view = self.review_text_view(prepared)
    let length = WordTree::new(prepared.document)
      .review_text_parts(paragraph)
      .fold(init=0, (sum, part) => sum + part.text.length())
    let (next, removed) = view.delete_review_boundary(
      paragraph, author, date, track,
    )
    if removed == Some(insertion.paragraph) {
      insertion = { ..insertion, paragraph, offset: insertion.offset + length, }
    }
    prepared = append_review_edit(prepared, next)
  }
  // At a collapsed paragraph boundary, Backspace and Delete move to opposite sides of retained markup.
  if text.is_empty() {
    if self.selection is Some(current) &&
      current.anchor == current.focus &&
      current.focus.paragraph == end.paragraph {
      insertion = {
        ..start,
        affinity: "after",
        bidiLevel: None,
        frameStart: None,
      }
    }
    return Some({
      ..prepared,
      edit: {
        ..prepared.edit,
        after: Some({ anchor: insertion, focus: insertion, }),
      },
    })
  }
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  for index, line in lines {
    if index > 0 {
      let next = self
        .review_text_view(prepared)
        .split_review_paragraph(insertion, author, date, track)
      insertion = next.edit.after.unwrap().focus
      prepared = append_review_edit(prepared, next)
    }
    if !line.is_empty() {
      let view = {
        ..self.review_text_view(prepared),
        selection: Some({ anchor: insertion, focus: insertion, }),
      }
      if view.prepare_review_text(
          { anchor: insertion, focus: insertion, },
          line,
          author,
          date,
          track~,
        )
        is Some(next) {
        insertion = next.edit.after.unwrap().focus
        prepared = append_review_edit(prepared, next)
      }
    }
  }
  Some({
    ..prepared,
    edit: {
      ..prepared.edit,
      after: Some({ anchor: insertion, focus: insertion, }),
    },
  })
}
