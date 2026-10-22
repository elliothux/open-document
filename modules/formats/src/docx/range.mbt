///|
fn Session::prepare_structural_range(
  self : Session,
  selection : Selection,
  text : String,
  check_graphemes~ : Bool = true,
) -> PreparedEdit raise @failure.Failure {
  let document = self.document()
  self.prepare_structural_range_in(document, selection, text, check_graphemes~)
}

///|
fn Session::prepare_structural_range_in(
  self : Session,
  document : @xml.Document,
  selection : Selection,
  text : String,
  check_graphemes~ : Bool = true,
) -> PreparedEdit raise @failure.Failure {
  let source = document.source()
  let tree = WordTree::new(document)
  let range = self.paragraph_range_in(
    document,
    tree,
    selection,
    structural=true,
    fields=true,
    math=true,
    tables=true,
    check_graphemes~,
  )
  self.check_drawing_range(tree, range)
  let start = range.start
  let end = range.end
  let first = tree.nodes[start.paragraph]
  let last = tree.nodes[end.paragraph]
  let parent = tree.nodes[first.parent]
  let siblings = tree.children[parent.id]
  let first_index = siblings.search(first.id).unwrap()
  let last_index = siblings.search(last.id).unwrap()
  let affected = range.paragraphs
  let texts = docx_texts(tree)
  let first_texts = texts.filter(item => item.paragraph == first.id)
  let last_texts = texts.filter(item => item.paragraph == last.id)
  let parts = text.split("\n").map(part => part.to_owned()).collect()
  let left = first_texts.map(node => inline_text(tree.nodes[node.id])).join("")
  let right = last_texts.map(node => inline_text(tree.nodes[node.id])).join("")
  let insertion = for node in first_texts; offset = 0 {
    let length = inline_text(tree.nodes[node.id]).length()
    if start.offset < offset + length ||
      (start.offset == offset + length && start.affinity == "before") {
      break Some(node.id)
    }
    continue offset + length
  } nobreak {
    first_texts.last().map(node => node.id)
  }
  let replacements : Map[Int, String] = Map([])
  let object_offsets : Map[Int, Int] = Map([])
  let mut insertion_offset = 0
  for node in first_texts; offset = 0 {
    let before = inline_text(tree.nodes[node.id])
    let keep = (start.offset - offset).clamp(min=0, max=before.length())
    let remove = if first.id == last.id {
      (end.offset - offset).clamp(min=0, max=before.length())
    } else {
      before.length()
    }
    let after = before[:keep].to_owned() +
      (if insertion == Some(node.id) { parts[0] } else { "" }) +
      before[remove:].to_owned()
    if insertion == Some(node.id) {
      insertion_offset = keep
    }
    let picture = ["drawing", "fldSimple", "oMath", "oMathPara"].contains(
      tree.nodes[node.id].name,
    )
    if picture && keep == remove {
      object_offsets[node.id] = if keep == 0 && insertion == Some(node.id) {
        parts[0].length()
      } else {
        0
      }
    }
    if before != after || (picture && keep != remove) {
      replacements[node.id] = after
    }
    continue offset + before.length()
  }
  for node in (if first.id == last.id { [] } else { last_texts }); offset = 0 {
    let before = inline_text(tree.nodes[node.id])
    let remove = (end.offset - offset).clamp(min=0, max=before.length())
    let after = before[remove:].to_owned()
    if ["drawing", "fldSimple", "oMath", "oMathPara"].contains(
        tree.nodes[node.id].name,
      ) &&
      remove == 0 {
      object_offsets[node.id] = 0
    }
    if before != after {
      replacements[node.id] = after
    }
    continue offset + before.length()
  }
  let changes : Array[@xml.SourceChange] = []
  if parts.length() > 1 {
    let tail = match insertion {
      Some(id) if first.id == last.id => {
        let before = inline_text(tree.nodes[id])
        let end_offset = (insertion_offset + end.offset - start.offset).min(
          before.length(),
        )
        before[end_offset:].to_owned()
      }
      _ => ""
    }
    if insertion is Some(id) {
      ignore(replacements.remove(id))
    }
    changes.append(
      tree.split_input(
        document,
        first.id,
        insertion,
        insertion_offset,
        parts,
        tail,
        merge=first.id != last.id,
        source_limit=self.opc.budget.entry_bytes.min(history_byte_limit / 2),
      ),
    )
  }
  let empty_content = if parts.length() == 1 &&
    first_texts.is_empty() &&
    !text.is_empty() {
    let content = inline_markup(
      text,
      self.opc.budget.entry_bytes.min(history_byte_limit / 2),
    )
    if tree.child(first.id, "r") is Some(run) {
      let run = tree.nodes[run]
      changes.push(
        if run.empty {
          {
            node: run.id,
            offset: run.opening_end - run.start - 2,
            length: 2,
            xml: ">\{content}</\{run.qualified}>",
          }
        } else {
          {
            node: run.id,
            offset: run.closing_start - run.start,
            length: 0,
            xml: content,
          }
        },
      )
      ""
    } else {
      let properties = tree.empty_run_properties(document, first.id)
      "<od:r xmlns:od=\"\{word_uri}\">\{properties}\{content}</od:r>"
    }
  } else {
    ""
  }
  if first.id != last.id {
    if !first.empty || parts.length() == 1 {
      changes.push(
        if first.empty {
          {
            node: parent.id,
            offset: first.opening_end - parent.start - 2,
            length: 2,
            xml: ">" + empty_content,
          }
        } else {
          {
            node: parent.id,
            offset: first.closing_start - parent.start,
            length: first.end - first.closing_start,
            xml: empty_content,
          }
        },
      )
    }
    for index = first_index + 1; index < last_index; index = index + 1 {
      let node = tree.nodes[siblings[index]]
      changes.push({
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: "",
      })
    }
    if last.empty {
      changes.push({
        node: parent.id,
        offset: last.start - parent.start,
        length: last.end - last.start,
        xml: "</\{first.qualified}>",
      })
    } else {
      changes.push({
        node: parent.id,
        offset: last.start - parent.start,
        length: last.opening_end - last.start,
        xml: "",
      })
      if tree.child(last.id, "pPr") is Some(id) {
        let node = tree.nodes[id]
        guard !source[node.start:node.end].contains("<!--") &&
          !source[node.start:node.end].contains("<?") else {
          @failure.reject(
            "protected-content", "Unknown paragraph property markup prevents merging",
          )
        }
        changes.push({
          node: parent.id,
          offset: node.start - parent.start,
          length: node.end - node.start,
          xml: "",
        })
      }
      changes.push({
        node: parent.id,
        offset: last.closing_start - parent.start,
        length: last.end - last.closing_start,
        xml: "</\{first.qualified}>",
      })
      let styles = self.styles([])
      for
        id in tree.children[last.id].filter(id => {
          (
            tree.nodes[id].uri == math_uri &&
            ["oMath", "oMathPara"].contains(tree.nodes[id].name)
          ) ||
          (
            tree.nodes[id].uri == word_uri &&
            [
              "r", "hyperlink", "fldSimple", "bookmarkStart", "bookmarkEnd", "commentRangeStart",
              "commentRangeEnd",
            ].contains(tree.nodes[id].name)
          )
        }) {
        let run = tree.nodes[id]
        let attributes = tree.namespace_additions(id, first.id)
        if !attributes.is_empty() {
          changes.push({
            node: run.id,
            offset: run.opening_end -
            run.start -
            (if run.empty { 2 } else { 1 }),
            length: 0,
            xml: attributes,
          })
        }
      }
      for id in tree.paragraph_runs(last.id, running=true) {
        if self.preserve_run_style(tree, styles, id, first.id) is Some(change) {
          changes.push(change)
        }
      }
    }
  }
  let updated = (if parts.length() == 1 {
      left[:start.offset].to_owned()
    } else {
      ""
    }) +
    parts.last().unwrap() +
    right[end.offset:].to_owned()
  let caret = @layout.grapheme_boundaries(updated)
    .iter()
    .find_first(offset => {
      offset >=
      (if parts.length() == 1 { start.offset } else { 0 }) +
      parts.last().unwrap().length()
    })
    .unwrap()
  let (candidate, xml) = self.edit_inline_text(
    document,
    replacements,
    source=changes,
    object_offsets~,
  )
  let updated_tree = WordTree::new(candidate)
  let paragraph = updated_tree.children[parent.id][first_index +
    parts.length() -
    1]
  if parts.length() > 1 {
    affected.append(
      updated_tree.children[parent.id][first_index + 1:first_index +
      parts.length()].to_owned(),
    )
  }
  let focus = {
    paragraph,
    offset: caret,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let prepared = self.restore_bookmarks({
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: affected,
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: if text.is_empty() {
      None
    } else if parts.length() > 1 || insertion is None {
      docx_texts(updated_tree)
      .iter()
      .find_first(node => node.paragraph == paragraph)
      .map(node => node.id)
    } else {
      insertion
    },
    join_group: false,
  })
  self.restore_comments(prepared)
}
