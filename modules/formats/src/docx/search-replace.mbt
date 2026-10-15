///|
priv struct ReplaceParagraph {
  nodes : Array[TextNode]
  starts : Array[Int]
  ends : Array[Int]
  boundaries : Array[Int]
}

///|
fn replacement_paragraph(
  tree : WordTree,
  nodes : Array[TextNode],
) -> ReplaceParagraph {
  let nodes = nodes.filter(node => !inline_text(tree.nodes[node.id]).is_empty())
  let starts : Array[Int] = []
  let ends : Array[Int] = []
  let out = StringBuilder()
  let mut offset = 0
  for item in nodes {
    starts.push(offset)
    let text = inline_text(tree.nodes[item.id])
    offset += text.length()
    ends.push(offset)
    out.write_string(text)
  }
  let text = out.to_string()
  { nodes, starts, ends, boundaries: @layout.grapheme_boundaries(text), }
}

///|
fn compare_positions(tree : WordTree, a : Position, b : Position) -> Int {
  if a.paragraph == b.paragraph {
    a.offset.compare(b.offset)
  } else {
    tree.nodes[a.paragraph].start.compare(tree.nodes[b.paragraph].start)
  }
}

///|
fn Session::plain_replacements(
  self : Session,
  targets : Array[Selection],
  text : String,
  tree : WordTree,
  paragraphs : Map[Int, ReplaceParagraph],
) -> PreparedEdit? raise @failure.Failure {
  let edits : Map[Int, Array[(Int, Int, String)]] = Map([])
  for target in targets {
    let frame = paragraphs[target.anchor.paragraph]
    let first = match
      frame.ends.binary_search_by(end => {
        if end <= target.anchor.offset {
          -1
        } else {
          1
        }
      }) {
      Err(index) => index
      Ok(_) => abort("Upper bound comparator cannot return equality")
    }
    for index = first
        index < frame.nodes.length() &&
       frame.starts[index] < target.focus.offset
        index = index + 1 {
      let item = frame.nodes[index]
      let start = (target.anchor.offset - frame.starts[index]).max(0)
      let end = (target.focus.offset - frame.starts[index]).min(
        inline_text(tree.nodes[item.id]).length(),
      )
      let values = edits.get(item.id).unwrap_or([])
      values.push((start, end, if index == first { text } else { "" }))
      edits[item.id] = values
    }
  }
  let changes : Map[Int, String] = Map([])
  for id, values in edits {
    let before = inline_text(tree.nodes[id])
    let out = StringBuilder()
    let mut cursor = 0
    for (start, end, value) in values {
      out.write_string(before[cursor:start].to_owned())
      out.write_string(value)
      cursor = end
    }
    out.write_string(before[cursor:].to_owned())
    let after = out.to_string()
    if before != after {
      changes[id] = after
    }
  }
  if changes.is_empty() {
    return None
  }
  let (document, xml) = self.edit_inline_text(self.document(), changes)
  let tree = WordTree::new(document)
  let first = targets[0].anchor
  let updated = docx_texts(tree)
    .filter(node => node.paragraph == first.paragraph)
    .map(node => inline_text(tree.nodes[node.id]))
    .join("")
  let boundaries = @layout.grapheme_boundaries(updated)
  let offset = first.offset + text.length()
  let index = match boundaries.binary_search(offset) {
    Ok(index) => index
    Err(index) => index
  }
  let focus = { ..first, offset: boundaries[index], }
  let affected = paragraphs.keys().collect()
  Some({
    document,
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: affected,
      bytes: edit_bytes(xml),
    },
    typing_text: None,
    join_group: false,
  })
}

///|
/// Replaces explicit nonoverlapping search ranges as one revision and history entry.
pub fn Session::replace_matches(
  self : Session,
  revision : Int,
  matches : Array[Selection],
  text : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard matches.length() <= 1000 &&
    text.length() <= command_limit &&
    @xml.valid_text(text) &&
    !text.contains("\r") else {
    @failure.reject(
      "invalid-operation", "Invalid replacement input or match count",
    )
  }
  if matches.is_empty() {
    return self.edit_state()
  }
  let escaped = @xml.escape_text(text)
  guard escaped.length().to_int64() * matches.length().to_int64() <=
    (history_byte_limit / 2).to_int64() else {
    @failure.reject(
      "limit-exceeded", "Replacement output exceeds history budget",
    )
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let by_paragraph : Map[Int, Array[TextNode]] = Map([])
  for node in self.texts {
    let nodes = by_paragraph.get(node.paragraph).unwrap_or([])
    nodes.push(node)
    by_paragraph[node.paragraph] = nodes
  }
  let paragraphs : Map[Int, ReplaceParagraph] = Map([])
  let targets = matches.map(selection => {
    for position in [selection.anchor, selection.focus] {
      guard tree.nodes.contains(position.paragraph) else {
        @failure.reject(
          "invalid-position", "Search target paragraph is missing",
        )
      }
      let frame = match paragraphs.get(position.paragraph) {
        Some(frame) => frame
        None => {
          tree.check_editable_paragraph(position.paragraph, part=self.main)
          let frame = replacement_paragraph(
            tree,
            by_paragraph.get(position.paragraph).unwrap_or([]),
          )
          paragraphs[position.paragraph] = frame
          frame
        }
      }
      validate_position(position, frame.boundaries)
    }
    let (start, end) = if compare_positions(
        tree,
        selection.anchor,
        selection.focus,
      ) <=
      0 {
      (selection.anchor, selection.focus)
    } else {
      (selection.focus, selection.anchor)
    }
    guard compare_positions(tree, start, end) < 0 else {
      @failure.reject(
        "invalid-operation", "Replacement ranges must not be empty",
      )
    }
    {
      anchor: { ..start, affinity: "after", frameStart: None, bidiLevel: None, },
      focus: { ..end, affinity: "before", frameStart: None, bidiLevel: None, },
    }
  })
  targets.sort_by((a, b) => compare_positions(tree, a.anchor, b.anchor))
  for index in 1..<targets.length() {
    guard compare_positions(
        tree,
        targets[index - 1].focus,
        targets[index].anchor,
      ) <=
      0 else {
      @failure.reject("invalid-operation", "Replacement ranges overlap")
    }
  }
  let structural = text.contains("\n") ||
    targets.any(target => target.anchor.paragraph != target.focus.paragraph)
  let prepared = if !structural {
    self.plain_replacements(targets, text, tree, paragraphs)
  } else {
    // shortcut: Structural batches reparse per match; combine source edits when larger batches are needed.
    guard document.source().length().to_int64() * targets.length().to_int64() <=
      67108864L else {
      @failure.reject(
        "limit-exceeded", "Structural replacement work budget exceeded",
      )
    }
    let mut candidate = document
    let edits : Array[@xml.Edit] = []
    let affected : Array[Int] = []
    let mut bytes = 0
    let mut selection = self.selection
    for index = targets.length() - 1; index >= 0; index = index - 1 {
      ignore(self.paragraph_range(tree, targets[index], structural=true))
      let working = {
        ..self,
        document: Some(candidate),
        texts: docx_texts(WordTree::new(candidate)),
        selection: None,
        typing_text: None,
        typing_format: None,
        input_group: None,
      }
      if working.prepare_range(targets[index], text, check_graphemes=false)
        is Some(prepared) {
        guard prepared.edit.bytes <= history_byte_limit - bytes else {
          @failure.reject(
            "limit-exceeded", "Replacement history budget exceeded",
          )
        }
        bytes += prepared.edit.bytes
        edits.append(prepared.edit.xml)
        for paragraph in prepared.edit.paragraphs {
          if !affected.contains(paragraph) {
            affected.push(paragraph)
          }
        }
        selection = prepared.edit.after
        candidate = prepared.document
      }
    }
    if edits.is_empty() {
      None
    } else {
      Some({
        document: candidate,
        edit: {
          xml: edits,
          parts: Map([]),
          created: Map([]),
          before: self.selection,
          after: selection,
          paragraphs: affected,
          bytes,
        },
        typing_text: None,
        join_group: false,
      })
    }
  }
  if prepared is Some(prepared) {
    self.commit_edit(prepared.edit, prepared.document)
    self.edit_result(prepared.edit.paragraphs)
  } else {
    self.edit_state()
  }
}

///|
pub fn Session::replace_all(
  self : Session,
  revision : Int,
  query : String,
  options : FindOptions,
  text : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let result = self.find_matches(query, options)
  guard !result.truncated else {
    @failure.reject("limit-exceeded", "Replace all exceeds the match limit")
  }
  guard result.matches.iter().all(item => item.2.is_empty()) else {
    @failure.reject("protected-content", "Search includes protected matches")
  }
  self.replace_matches(revision, result.matches.map(item => item.0), text)
}
