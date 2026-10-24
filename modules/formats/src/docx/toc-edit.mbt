///|
pub(all) enum TocEdit {
  InsertToc(Int)
  UpdateToc(Int)
  DeleteToc(Int)
}

///|
/// Inserts a native TOC before the selected body paragraph, or replaces/removes one complete supported field.
pub fn Session::edit_table_of_contents(
  self : Session,
  revision : Int,
  change : TocEdit,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  let original = self.document()
  let tree = WordTree::new(original)
  ignore(self.editable_page_section(tree))
  let body = tree.child(0, "body").unwrap()
  let (old, first, last, instruction, hyperlink) = match change {
    InsertToc(levels) => {
      guard levels >= 1 && levels <= 9 else {
        @failure.reject(
          "invalid-operation", "Table of contents depth must be between one and nine",
        )
      }
      guard self.selection is Some(selection) &&
        tree.nodes.get(selection.focus.paragraph) is Some(p) &&
        p.parent == body else {
        @failure.reject(
          "invalid-position", "Select an ordinary body paragraph for the table of contents",
        )
      }
      tree.check_editable_paragraph(
        p.id,
        part=self.main,
        pictures=true,
        fields=true,
        math=true,
        notes=true,
      )
      (None, 1, levels, " TOC \\o \"1-\{levels}\" \\h \\z \\u ", true)
    }
    UpdateToc(id) | DeleteToc(id) => {
      guard tree.contents.get(id) is Some(toc) &&
        toc.paragraphs[0] == id &&
        toc.reason.is_empty() else {
        @failure.reject(
          "protected-content", "Select one complete supported table of contents",
        )
      }
      for paragraph in toc.paragraphs {
        for node in tree.descendants(paragraph) {
          let n = tree.nodes[node]
          guard !tree.is_bookmark(node) &&
            !tree.is_comment_marker(node) &&
            !(n.uri == word_uri &&
            (revision_element(n.name) || note_reference(n))) else {
            @failure.reject(
              "protected-content", "Retained annotations protect the table of contents result",
            )
          }
        }
      }
      (Some(toc), toc.first, toc.last, toc.instruction, toc.hyperlink)
    }
  }
  let flow = self.flow()
  let layout = @layout.paginate(probe, flow, profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Table of contents editing requires a complete layout",
    )
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let deleting = change is DeleteToc(_)
  let (entries, source_changes) = if deleting {
    ([], [])
  } else {
    self.toc_entries(tree, flow, layout, first, last)
  }
  let styles : Map[Int, String] = Map([])
  for entry in entries {
    if !styles.contains(entry.level) {
      styles[entry.level] = self.builtin_paragraph_style(
        "TOC\{entry.level}",
        "toc \{entry.level}",
        parts,
        edits,
        created,
      )
    }
  }
  let width = flow.columns.width_at(flow.page, flow.page.left)
  let mut markup = if deleting {
    ""
  } else {
    toc_markup(entries, styles, instruction, hyperlink, width)
  }
  let start = old
    .map(toc => {
      tree.nodes[if deleting {
        toc.control.unwrap_or(toc.paragraphs[0])
      } else {
        toc.paragraphs[0]
      }].start
    })
    .unwrap_or_else(() => {
      tree.nodes[self.selection.unwrap().focus.paragraph].start
    })
  let finish = old
    .map(toc => {
      tree.nodes[if deleting {
        toc.control.unwrap_or(toc.paragraphs.last().unwrap())
      } else {
        toc.paragraphs.last().unwrap()
      }].end
    })
    .unwrap_or(start)
  if deleting &&
    tree.children[body].all(id => {
      tree.nodes[id].name == "sectPr" ||
      old.unwrap().paragraphs.contains(id) ||
      old.unwrap().control == Some(id)
    }) {
    markup = "<od:p xmlns:od=\"\{word_uri}\"/>"
  }
  guard markup.length() <=
    self.opc.budget.entry_bytes.min(history_byte_limit / 2) else {
    @failure.reject("limit-exceeded", "Table of contents source exceeds budget")
  }
  source_changes.push({
    node: body,
    offset: start - tree.nodes[body].start,
    length: finish - start,
    xml: markup,
  })
  let (initial, step) = original.edit_source(source_changes)
  let mut candidate = initial
  let steps = [step]
  let mut expected = entries
  for round in 0..<8 {
    let updated = WordTree::new(candidate)
    if !deleting {
      for toc in updated.contents.values() {
        guard tree.nodes.contains(toc.paragraphs[0]) || toc.reason.is_empty() else {
          @failure.reject("unsupported-layout", toc.reason)
        }
      }
    }
    let view = { ..self, document: Some(candidate), parts, }
    let candidate_flow = view.flow()
    let layout = @layout.paginate(probe, candidate_flow, profile, images)
    guard layout.diagnostics.is_empty() else {
      @failure.reject(
        "unsupported-layout",
        "Table of contents result requires a complete layout: " +
        layout.diagnostics.join("; ")[:8192].to_owned(),
      )
    }
    if !deleting {
      let (next, changes) = view.toc_entries(
        updated, candidate_flow, layout, first, last,
      )
      if next != expected {
        guard round < 7 else {
          @failure.reject(
            "unsupported-layout", "Table of contents labels did not converge",
          )
        }
        for entry in next {
          if !styles.contains(entry.level) {
            styles[entry.level] = self.builtin_paragraph_style(
              "TOC\{entry.level}",
              "toc \{entry.level}",
              parts,
              edits,
              created,
            )
          }
        }
        let id = updated.order
          .iter()
          .find_first(id => {
            !tree.nodes.contains(id) &&
            updated.contents
            .get(id)
            .map(toc => toc.paragraphs[0] == id)
            .unwrap_or(false)
          })
          .unwrap()
        let toc = updated.contents[id]
        let start = updated.nodes[id].start
        let finish = updated.nodes[toc.paragraphs.last().unwrap()].end
        let markup = toc_markup(next, styles, instruction, hyperlink, width)
        guard markup.length() <=
          self.opc.budget.entry_bytes.min(history_byte_limit / 2) else {
          @failure.reject(
            "limit-exceeded", "Table of contents source exceeds budget",
          )
        }
        changes.push({
          node: body,
          offset: start - updated.nodes[body].start,
          length: finish - start,
          xml: markup,
        })
        let (reflowed, step) = candidate.edit_source(changes)
        candidate = reflowed
        steps.push(step)
        expected = next
        let bytes = steps
          .iter()
          .fold(init=xml_part_edit_bytes(edits, created), (sum, step) => {
            sum + edit_bytes(step)
          })
        guard bytes <= history_byte_limit else {
          @failure.reject(
            "limit-exceeded", "Table of contents history exceeds budget",
          )
        }
        continue
      }
    }
    let fields = updated.order.filter(id => {
      updated.nodes[id].uri == word_uri &&
      updated.nodes[id].name == "fldSimple" &&
      !tree.nodes.contains(id)
    })
    let (cached, step) = candidate.edit_text(
      self.field_cache_changes(updated, fields, layout),
    )
    candidate = cached
    steps.push(step)
    break
  }
  if candidate.source() == original.source() &&
    edits.is_empty() &&
    created.is_empty() {
    return self.edit_state()
  }
  let mut bytes = xml_part_edit_bytes(edits, created)
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Table of contents history exceeds budget",
      )
    }
    bytes += size
  }
  let pending = self.typing_format
  let before = self.selection.map(selection => selection.without_visual_hints())
  let mut after = before
  if after is Some(selection) &&
    old
    .map(toc => {
      toc.paragraphs.contains(selection.anchor.paragraph) ||
      toc.paragraphs.contains(selection.focus.paragraph)
    })
    .unwrap_or(false) {
    after = None
  }
  let affected = { ..self, document: Some(candidate), parts, }.flow().paragraphs.map(p => {
      p.id
    },
  )
  if old is Some(toc) {
    affected.append(toc.paragraphs)
  }
  self.commit_edit(
    {
      xml: steps,
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after,
      paragraphs: affected,
      bytes,
    },
    candidate,
    parts~,
  )
  if after == before {
    self.typing_format = pending
  }
  self.edit_result(affected)
}
