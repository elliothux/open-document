///|
priv struct RevisionEntry {
  node : Int32
  source_id : String
  kind : String
  element : String
  author : String
  date : String
  text : String
  paragraph : Int32?
  reason : String
}

///|
fn revision_element(name : String) -> Bool {
  [
    "ins", "del", "moveFrom", "moveTo", "rPrChange", "pPrChange", "tblPrChange",
    "trPrChange", "tcPrChange", "sectPrChange", "tblGridChange",
  ].contains(name)
}

///|
fn WordTree::check_text_revision(
  self : WordTree,
  id : Int32,
) -> Int32 raise @failure.Failure {
  if self.is_paragraph_revision(id) {
    let paragraph = self.check_paragraph_revision(id)
    ignore(self.review_text_parts(paragraph))
    return paragraph
  }
  let node = self.nodes[id]
  guard ["ins", "del"].contains(node.name) &&
    node.uri == word_uri &&
    node.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    node.text.trim().is_empty() &&
    self.nodes.get(node.parent) is Some(paragraph) &&
    paragraph.uri == word_uri &&
    paragraph.name == "p" else {
    @failure.reject(
      "protected-content", "Only ordinary paragraph text insertions and deletions can be resolved",
    )
  }
  ignore(comment_key(node.attribute("id", uri=word_uri).unwrap_or("")))
  self.check_revision_paragraph(paragraph.id)
  let fragment = self.source[node.start:node.end]
  guard !fragment.contains("<!--") &&
    !fragment.contains("<?") &&
    !self.children[id].is_empty() else {
    @failure.reject(
      "protected-content", "Opaque or empty revisions are protected",
    )
  }
  for run in self.children[id] {
    let item = self.nodes[run]
    guard item.uri == word_uri &&
      item.name == "r" &&
      item.text.trim().is_empty() &&
      item.attributes.all(a => {
        a.uri == word_uri && ["rsidR", "rsidDel", "rsidRPr"].contains(a.name)
      }) else {
      @failure.reject(
        "protected-content", "Revision requires ordinary text runs without nested changes or identities",
      )
    }
    for child in self.children[run] {
      let content = self.nodes[child]
      guard content.uri == word_uri else {
        @failure.reject(
          "protected-content", "Foreign revision content is protected",
        )
      }
      if content.name == "rPr" {
        self.check_review_properties(child)
      } else if content.name ==
        (if node.name == "del" { "delText" } else { "t" }) {
        self.check_field_text(child)
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
            "protected-content", "Fields, drawings and structural revision content are protected",
          )
        }
      }
    }
  }
  paragraph.id
}

///|
fn WordTree::revision_entries(
  self : WordTree,
) -> Array[RevisionEntry] raise @failure.Failure {
  let body = self.child(0, "body").unwrap()
  let entries : Array[RevisionEntry] = []
  let mut units = 0
  for id in self.descendants(body) {
    let node = self.nodes[id]
    guard node.uri == word_uri && revision_element(node.name) else { continue }
    guard entries.length() < 4096 else {
      @failure.reject("limit-exceeded", "Revision catalog exceeds 4096 entries")
    }
    let (paragraph, reason) = try {
      let paragraph = if node.name == "tcPrChange" {
        self.check_cell_property_revision(id)
      } else if node.name == "tblPrChange" {
        self.check_table_property_revision(id)
      } else if node.name == "trPrChange" {
        self.check_row_property_revision(id)
      } else if self.is_row_revision(id) {
        self.check_row_revision(id)
      } else if ["rPrChange", "pPrChange"].contains(node.name) {
        self.check_property_revision(id)
      } else {
        self.check_text_revision(id)
      }
      (Some(paragraph), "")
    } catch {
      @failure.Failure(message~, ..) => (None, message)
    }
    let preview = if self.is_row_revision(id) ||
      ["trPrChange", "tblPrChange", "tcPrChange"].contains(node.name) {
      self.nodes[node.parent].parent
    } else if ["rPrChange", "pPrChange"].contains(node.name) &&
      paragraph is Some(paragraph) {
      if node.name == "rPrChange" {
        self.nodes[node.parent].parent
      } else {
        paragraph
      }
    } else {
      id
    }
    let text = StringBuilder()
    let mut length = 0
    for child in self.descendants(preview) {
      let item = self.nodes[child]
      if item.uri != word_uri ||
        !["t", "delText", "br", "cr", "tab"].contains(item.name) {
        continue
      }
      let value = inline_text(item)
      guard value.length() <= 32767 - length &&
        value.length() <= 1048576 - units else {
        @failure.reject(
          "limit-exceeded", "Revision text exceeds catalog budget",
        )
      }
      length += value.length()
      units += value.length()
      text.write_string(value)
    }
    let author = node.attribute("author", uri=word_uri).unwrap_or("")
    let date = node.attribute("date", uri=word_uri).unwrap_or("")
    let source_id = node.attribute("id", uri=word_uri).unwrap_or("")
    guard author.length() <= 255 &&
      date.length() <= 128 &&
      source_id.length() <= 128 else {
      @failure.reject(
        "limit-exceeded", "Revision metadata exceeds catalog budget",
      )
    }
    entries.push({
      node: id,
      source_id,
      element: node.name,
      kind: if self.is_row_revision(id) {
        if node.name == "ins" {
          "rowInsert"
        } else {
          "rowDelete"
        }
      } else {
        match node.name {
          "ins" => "insert"
          "del" => "delete"
          "rPrChange" => "characterFormat"
          "pPrChange" => "paragraphFormat"
          "trPrChange" => "rowFormat"
          "tblPrChange" => "tableFormat"
          "tcPrChange" => "cellFormat"
          _ => "unsupported"
        }
      },
      author,
      date,
      text: if self.is_paragraph_revision(id) {
        "¶"
      } else {
        text.to_string()
      },
      paragraph,
      reason,
    })
  }
  entries
}

///|
fn Session::check_revision_protection(
  self : Session,
) -> Unit raise @failure.Failure {
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let targets = tree.children[0].filter(id => {
      tree.nodes[id].uri == word_uri &&
      tree.nodes[id].name == "documentProtection"
    })
    guard targets.length() <= 1 &&
      targets.all(id => {
        ["0", "false", "off"].contains(
          tree.nodes[id].attribute("enforcement", uri=word_uri).unwrap_or("0"),
        )
      }) else {
      @failure.reject(
        "protected-content", "Document protection prevents resolving revisions",
      )
    }
  }
}

///|
/// Lists body and ordinary table-cell revisions; unsupported structures retain a per-entry reason.
pub fn Session::revisions(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let entries = WordTree::new(self.document()).revision_entries()
  let reason = try {
    self.check_revision_protection()
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
  {
    "revision": revision,
    "reason": reason,
    "items": entries.map(fn(entry) -> Json {
      {
        "id": entry.node.to_string(),
        "sourceId": entry.source_id,
        "kind": entry.kind,
        "element": entry.element,
        "author": entry.author,
        "date": entry.date,
        "text": entry.text,
        "paragraph": entry.paragraph
        .map(value => Json(value))
        .unwrap_or(Json::null()),
        "reason": entry.reason,
      }
    }),
  }
}

///|
fn revision_retained_text(
  document : @xml.Document,
  tree : WordTree,
  id : Int32,
  limit : Int32,
) -> String raise @failure.Failure {
  let content = tree.children[id]
    .map(run => tree.standalone_markup(document, run))
    .join("")
  guard content.length() <= limit else {
    @failure.reject("limit-exceeded", "Retained revision source exceeds budget")
  }
  if tree.nodes[id].name == "ins" {
    return content
  }
  let fragment = @xml.Document::parse(
    @utf8.encode(
      "<od:revision xmlns:od=\"urn:open-document:revision\">" +
      content +
      "</od:revision>",
    ),
    "revision-result",
    128,
    limit,
  )
  let changes : Array[@xml.SourceChange] = []
  for node in fragment.nodes() {
    if node.uri == word_uri && node.name == "delText" {
      let name = node.qualified[:node.qualified.length() - 7].to_owned() + "t"
      changes.push({
        node: node.id,
        offset: 1,
        length: node.qualified.length(),
        xml: name,
      })
      if !node.empty {
        changes.push({
          node: node.id,
          offset: node.closing_start - node.start + 2,
          length: node.qualified.length(),
          xml: name,
        })
      }
    }
  }
  let result = fragment.edit_source(changes).0
  let root = result.nodes()[0]
  result.source()[root.opening_end:root.closing_start].to_owned()
}

///|
/// Resolves explicit catalog entries atomically and records one exact source history item.
pub fn Session::resolve_revisions(
  self : Session,
  revision : Int32,
  ids : Array[String],
  accept : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_revision_protection()
  guard !ids.is_empty() && ids.length() <= 4096 else {
    @failure.reject("invalid-operation", "Select 1–4096 revisions")
  }
  let wanted : Map[String, Bool] = Map([])
  for id in ids {
    guard !wanted.contains(id) && !id.is_empty() && id.length() <= 16 else {
      @failure.reject(
        "invalid-operation", "Invalid or duplicate revision identity",
      )
    }
    wanted[id] = true
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let entries = tree
    .revision_entries()
    .filter(entry => wanted.contains(entry.node.to_string()))
  guard entries.length() == ids.length() else {
    @failure.reject("invalid-operation", "Revision entry no longer exists")
  }
  let affected : Array[Int32] = []
  let paragraph_marks = entries.filter(entry => {
    tree.is_paragraph_revision(entry.node)
  })
  let mark_ids = Set::from_array(paragraph_marks.map(entry => entry.node))
  let row_marks = entries.filter(entry => tree.is_row_revision(entry.node))
  let row_ids = Set::from_array(row_marks.map(entry => entry.node))
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let mut units = 0
  for entry in entries {
    guard entry.reason.is_empty() && entry.paragraph is Some(paragraph) else {
      @failure.reject("protected-content", entry.reason)
    }
    if !affected.contains(paragraph) {
      affected.push(paragraph)
    }
  }
  let mut candidate = document
  let steps : Array[@xml.Edit] = []
  let mut bytes = 0
  // Resolve inner property changes before unwrapping or removing text revisions.
  for
    kind in [
      "characterFormat", "paragraphFormat", "tableFormat", "rowFormat", "cellFormat",
      "text",
    ] {
    let tree = WordTree::new(candidate)
    let changes : Array[@xml.SourceChange] = []
    for entry in entries {
      if mark_ids.contains(entry.node) || row_ids.contains(entry.node) {
        continue
      }
      let properties = [
        "characterFormat", "paragraphFormat", "tableFormat", "rowFormat", "cellFormat",
      ].contains(entry.kind)
      if (if properties { entry.kind } else { "text" }) != kind {
        continue
      }
      let change = if properties {
        property_revision_change(candidate, tree, entry.node, accept)
      } else {
        let retain = (entry.kind == "insert") == accept
        let markup = if retain {
          revision_retained_text(candidate, tree, entry.node, limit)
        } else {
          ""
        }
        let node = tree.nodes[entry.node]
        {
          node: node.parent,
          offset: node.start - tree.nodes[node.parent].start,
          length: node.end - node.start,
          xml: markup,
        }
      }
      guard change.xml.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Revision result exceeds source budget",
        )
      }
      units += change.xml.length()
      changes.push(change)
    }
    if !changes.is_empty() {
      let (updated, step) = candidate.edit_source(changes)
      bytes += edit_bytes(step)
      guard bytes <= history_byte_limit else {
        @failure.reject("limit-exceeded", "Revision history exceeds budget")
      }
      candidate = updated
      steps.push(step)
    }
  }
  // Resolve paragraph marks from the end so each earlier paragraph identity survives.
  for entry in paragraph_marks.rev() {
    let tree = WordTree::new(candidate)
    let paragraph = entry.paragraph.unwrap()
    guard tree.paragraph_revision(paragraph) is Some(mark) &&
      tree.nodes[mark].attribute("id", uri=word_uri) == Some(entry.source_id) else {
      @failure.reject(
        "protected-content", "Paragraph revision changed during review",
      )
    }
    let keep_boundary = (entry.kind == "insert") == accept
    let (updated, step) = if keep_boundary {
      let node = tree.nodes[mark]
      candidate.edit_source([
        {
          node: node.parent,
          offset: node.start - tree.nodes[node.parent].start,
          length: node.end - node.start,
          xml: "",
        },
      ])
    } else {
      let (updated, step, removed) = self.merge_review_paragraphs(
        candidate, paragraph,
      )
      if !affected.contains(removed) {
        affected.push(removed)
      }
      (updated, step)
    }
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Revision history exceeds budget")
    }
    bytes += size
    candidate = updated
    steps.push(step)
  }
  if !row_marks.is_empty() {
    let next = WordTree::new(candidate)
    let row_marks = row_marks.map(entry => {
      let row = tree.nodes[tree.nodes[entry.node].parent].parent
      guard next.row_revision(row) is Some(mark) &&
        next.nodes[mark].attribute("id", uri=word_uri) == Some(entry.source_id) else {
        @failure.reject(
          "protected-content", "Row revision changed during review",
        )
      }
      { ..entry, node: mark, }
    })
    let (updated, row_steps, row_affected, size) = self.resolve_row_revisions(
      candidate, row_marks, accept,
    )
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Revision history exceeds budget")
    }
    candidate = updated
    steps.append(row_steps)
    affected.append(row_affected)
    bytes += size
  }
  if entries.any(entry => {
      ["rowFormat", "tableFormat", "cellFormat"].contains(entry.kind)
    }) {
    let tables = Set::from_array(
      entries
      .filter(entry => {
        ["rowFormat", "tableFormat", "cellFormat"].contains(entry.kind)
      })
      .map(entry => {
        let owner = tree.nodes[tree.nodes[entry.node].parent].parent
        if entry.kind == "tableFormat" {
          owner
        } else if entry.kind == "cellFormat" {
          tree.nodes[tree.nodes[owner].parent].parent
        } else {
          tree.nodes[owner].parent
        }
      }),
    )
    let flow = self.flow_from(candidate)
    for table in flow.tables.filter(table => tables.contains(table.id)) {
      check_margin_layout(
        table,
        page_area_for_position(flow, table_start_position(table)).0,
      )
      for r in 0..<table.headerRows {
        guard table.rowSpans[r].all(span => span <= table.headerRows - r) else {
          @failure.reject(
            "protected-content", "Reviewed header boundary crosses a vertical merge",
          )
        }
      }
    }
  }
  let next = WordTree::new(candidate)
  let after = if self.selection is Some(selection) &&
    !affected.contains(selection.anchor.paragraph) &&
    !affected.contains(selection.focus.paragraph) {
    self.selection
  } else {
    (affected + next.order)
    .iter()
    .find_first(id => {
      try {
        if next.has_review_markup(id) {
          ignore(next.review_text_parts(id))
        } else {
          next.check_editable_paragraph(id, part=self.main, pictures=true)
        }
      } catch {
        @failure.Failure(..) => return false
      }
      true
    })
    .map(id => {
      let focus : Position = {
        paragraph: id,
        offset: 0,
        affinity: "after",
        bidiLevel: None,
        frameStart: None,
      }
      { anchor: focus, focus, }
    })
  }
  self.commit_edit(
    {
      xml: steps,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after,
      paragraphs: affected,
      bytes,
    },
    candidate,
    tracking_edit=true,
  )
  self.edit_result(affected)
}
