///|
fn Session::hyperlink_relationship(
  self : Session,
  target : String,
  links : Map[String, @opc.Relationship],
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let kind = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink"
  if links
    .values()
    .find_first(r => r.external && r.kind == kind && r.target == target)
    is Some(link) {
    return link.id
  }
  let id = for i in 1..<=16384 {
    let id = "odLink\{i}"
    if !links.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Hyperlink identities exhausted")
  }
  let segments = self.main.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(s => s.to_owned())
    .join("/")
  let path = (if directory.is_empty() { "" } else { directory + "/" }) +
    "_rels/" +
    segments.last().unwrap().to_owned() +
    ".rels"
  let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
  let markup = "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{kind}\" Target=\"\{property_attribute(target)}\" TargetMode=\"External\"/>"
  if self.opc.names.contains(path.to_lower()) || parts.contains(path) {
    let (candidate, edit) = append_part_xml(self.part_xml(path), markup)
    parts[path] = candidate
    edits[path] = [edit]
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
      ),
      path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[path] = document
    created[path] = document
  }
  id
}

///|
fn hyperlink_opening(
  tree : WordTree,
  document : @xml.Document,
  old : Int?,
  relation : String,
  paragraph : Int,
) -> (String, String) raise @failure.Failure {
  if old is Some(id) {
    let node = tree.nodes[id]
    let attribute = node.attributes
      .iter()
      .find_first(a => {
        a.uri ==
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships" &&
        a.name == "id"
      })
      .unwrap()
    let source = document.source()
    (
      source[node.start:attribute.start].to_owned() +
      property_attribute(relation) +
      source[attribute.end:node.opening_end].to_owned(),
      "</\{node.qualified}>",
    )
  } else {
    // Wrapping must not shadow the original runs' namespace bindings.
    let p = tree.nodes[paragraph].qualified
    let name = p[:p.length() - 1].to_owned() + "hyperlink"
    let bindings = tree.namespace_bindings(paragraph)
    let prefix = for i in 1..<=16384 {
      let prefix = "odLink\{i}"
      if !bindings.contains(prefix) {
        break prefix
      }
    } nobreak {
      @failure.reject(
        "limit-exceeded", "Hyperlink namespace identities exhausted",
      )
    }
    (
      "<\{name} xmlns:\{prefix}=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" \{prefix}:id=\"\{property_attribute(relation)}\">",
      "</\{name}>",
    )
  }
}

///|
fn hyperlink_changes(
  document : @xml.Document,
  range : ParagraphRange,
  selected : Array[Int],
  relation : String?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = WordTree::new(document)
  let changes : Array[@xml.SourceChange] = []
  let picked = Map::from_array(selected.map(id => (id, true)))
  let mut units = 0
  fn change(
    paragraph : Int,
    start : Int,
    end : Int,
    markup : String,
  ) -> Unit raise @failure.Failure {
    units += markup.length()
    guard units <= history_byte_limit / 2 else {
      @failure.reject("limit-exceeded", "Hyperlink source exceeds budget")
    }
    changes.push({
      node: paragraph,
      offset: start - tree.nodes[paragraph].start,
      length: end - start,
      xml: markup,
    })
  }
  for p in range.paragraphs {
    let runs = tree.paragraph_runs(p)
    let mut i = 0
    while i < runs.length() {
      if !picked.contains(runs[i]) {
        i += 1
        continue
      }
      let first = tree.nodes[runs[i]]
      let mut j = i
      while j + 1 < runs.length() &&
            picked.contains(runs[j + 1]) &&
            tree.nodes[runs[j + 1]].parent == first.parent {
        j += 1
      }
      let last = tree.nodes[runs[j]]
      let old = tree.run_hyperlink(first.id)
      let (opening, closing) = relation
        .map(id => hyperlink_opening(tree, document, old, id, p))
        .unwrap_or(("", ""))
      if old is Some(id) {
        let node = tree.nodes[id]
        let children = tree.children[id]
        let old_opening = document.source()[node.start:node.opening_end].to_owned()
        let old_closing = "</\{node.qualified}>"
        if children.get(0) == Some(first.id) {
          change(p, node.start, node.opening_end, opening)
        } else {
          change(p, first.start, first.start, old_closing + opening)
        }
        if children.last() == Some(last.id) {
          change(p, node.closing_start, node.end, closing)
        } else {
          change(p, last.end, last.end, closing + old_opening)
        }
        if relation is None {
          for k in i..<=j {
            let run = tree.nodes[runs[k]]
            let extra = tree.namespace_additions(run.id, p)
            if !extra.is_empty() {
              let at = run.opening_end - (if run.empty { 2 } else { 1 })
              change(p, at, at, extra)
            }
          }
        }
      } else if relation is Some(_) {
        change(p, first.start, first.start, opening)
        change(p, last.end, last.end, closing)
      }
      i = j + 1
    }
  }
  changes
}

///|
/// Edits an external hyperlink; a caret outside a link requires explicit display text.
pub fn Session::set_hyperlink(
  self : Session,
  revision : Int,
  selection : Selection,
  target : String?,
  text~ : String? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if target is Some(target) {
    check_hyperlink_target(target)
  }
  if text is Some(text) {
    guard target is Some(_) &&
      !text.is_empty() &&
      text.length() <= command_limit &&
      @xml.valid_text(text) &&
      !text.contains("\n") &&
      !text.contains("\r") &&
      !text.contains("\t") &&
      !text.contains("\u2028") else {
      @failure.reject(
        "invalid-operation", "Hyperlink display text requires bounded plain text and a target",
      )
    }
  }
  let original = self.document()
  let range = self.hyperlink_range(original, selection)
  let selected = { anchor: range.start, focus: range.end, }
  let links = self.hyperlink_relationships()
  let original_tree = WordTree::new(original)
  let values = self
    .hyperlink_runs(original_tree, range)
    .map(run => hyperlink_target(original_tree, run, links))
  if text is None &&
    (target is None || !values.is_empty()) &&
    values.all(value => value == target) {
    return self.edit_result([])
  }
  guard text is Some(_) ||
    (
      !values.is_empty() &&
      (
        range.start.paragraph != range.end.paragraph ||
        range.start.offset != range.end.offset
      )
    ) ||
    values.any(value => value is Some(_)) else {
    @failure.reject(
      "invalid-operation", "Enter display text to create a hyperlink at a caret",
    )
  }
  let prepared = if text is Some(text) {
    self.prepare_range(selected, text)
  } else {
    None
  }
  let mut document = prepared.map(p => p.document).unwrap_or(original)
  let after = prepared
    .bind(p => p.edit.after)
    .map(s => {
      anchor: { ..s.anchor, affinity: "before", },
      focus: { ..s.focus, affinity: "before", },
    })
    .unwrap_or(selection.without_visual_hints())
  let selected = if text is Some(text) {
    {
      anchor: range.start,
      focus: { ..range.start, offset: range.start.offset + text.length(), },
    }
  } else {
    selected
  }
  let range = self.formatting_range(document, selected)
  let tree = WordTree::new(document)
  for run in self.hyperlink_runs(tree, range) {
    guard !tree.children[run].any(id => tree.nodes[id].name == "drawing") else {
      @failure.reject(
        "protected-content", "Hyperlinks around pictures require editing support",
      )
    }
  }
  let xml = prepared.map(p => p.edit.xml.copy()).unwrap_or([])
  if self.format_character_document(
      document,
      selected,
      CharacterFormat::new(),
      split=true,
    )
    is Some((candidate, edit)) {
    document = candidate
    xml.push(edit)
  }
  let tree = WordTree::new(document)
  let changed = self
    .hyperlink_runs(tree, range)
    .filter(run => hyperlink_target(tree, run, links) != target)
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let relation = if changed.is_empty() {
    None
  } else {
    target.map(target => {
      self.hyperlink_relationship(target, links, parts, edits, created)
    })
  }
  let changes = hyperlink_changes(document, range, changed, relation)
  if !changes.is_empty() {
    let (candidate, edit) = document.edit_source(changes)
    document = candidate
    xml.push(edit)
  }
  if xml.is_empty() {
    return self.edit_result([])
  }
  let mut bytes = xml_part_edit_bytes(edits, created)
  for edit in xml {
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Hyperlink history exceeds budget")
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
      after: Some(after),
      paragraphs: range.paragraphs,
      bytes,
    },
    document,
    parts~,
  )
  self.typing_format = None
  self.typing_text = None
  self.edit_result(range.paragraphs)
}
