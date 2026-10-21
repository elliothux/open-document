///|
fn Session::running_target(
  self : Session,
  tree : WordTree,
  kind : String,
  variant : String,
) -> (Int?, Int?, String?) raise @failure.Failure {
  guard ["header", "footer"].contains(kind) else {
    @failure.reject("invalid-operation", "Invalid header or footer kind")
  }
  let section = self.editable_page_section(tree)
  guard ["default", "first", "even"].contains(variant) else {
    @failure.reject("invalid-operation", "Invalid running area variant")
  }
  let all = section
    .map(id => {
      tree.children[id].filter(id => tree.nodes[id].name == kind + "Reference")
    })
    .unwrap_or([])
  for value in ["default", "first", "even"] {
    guard all
      .filter(id => {
        tree.nodes[id].attribute("type", uri=word_uri) == Some(value)
      })
      .length() <=
      1 else {
      @failure.reject("protected-content", "Duplicate running area variant")
    }
  }
  let references = all.filter(id => {
    tree.nodes[id].attribute("type", uri=word_uri) == Some(variant)
  })
  let reference = references.get(0)
  let part = reference.map(id => self.running_part(tree, id, kind))
  (section, reference, part)
}

///|
fn Session::editable_running(
  self : Session,
  tree : WordTree,
  kind : String,
  variant : String,
) -> (Int?, Int?, String?, Array[@layout.Paragraph]) raise @failure.Failure {
  let (section, reference, part) = self.running_target(tree, kind, variant)
  if part is Some(part) {
    let source = self.part_xml(part).source()
    let root = WordTree::new(self.part_xml(part)).nodes[0]
    guard !source[root.start:root.end].contains("<!--") &&
      !source[root.start:root.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated header or footer source is protected",
      )
    }
  }
  let diagnostics : Array[String] = []
  let styles = self.styles(diagnostics)
  let paragraphs = part
    .map(part => {
      self.running_paragraphs(
        part,
        kind,
        styles,
        diagnostics,
        tree.page_background().unwrap_or("ffffff"),
        variant,
      )
    })
    .unwrap_or([])
  let mut units = (paragraphs.length() - 1).max(0)
  for paragraph in paragraphs {
    for span in paragraph.spans {
      let count = if span.field.is_empty() { span.text.length() } else { 1 }
      guard count <= 8192 - units else {
        @failure.reject(
          "protected-content", "Header or footer exceeds the editing limit",
        )
      }
      units += count
    }
  }
  ignore(
    normalize_running_content(
      running_content(paragraphs, self.running_links(part, paragraphs)),
    ),
  )
  guard diagnostics.is_empty() else {
    @failure.reject("protected-content", diagnostics[0])
  }
  (section, reference, part, paragraphs)
}

///|
/// Reads ordered text, links and page fields from one single-section running area.
pub fn Session::running_area(
  self : Session,
  revision : Int,
  kind : String,
  variant : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["header", "footer"].contains(kind) else {
    @failure.reject("invalid-operation", "Invalid header or footer kind")
  }
  guard ["default", "first", "even"].contains(variant) else {
    @failure.reject("invalid-operation", "Invalid running area variant")
  }
  let tree = WordTree::new(self.document())
  let mut shared = false
  let (section, _, part, paragraphs) = try {
    let (_, _, part) = self.running_target(tree, kind, variant)
    shared = self.running_shared(tree, part)
    self.editable_running(tree, kind, variant)
  } catch {
    @failure.Failure(message~, ..) =>
      return {
        "revision": revision,
        "content": [{ "text": "" }],
        "distance": 0,
        "differentFirst": false,
        "differentEven": false,
        "shared": shared,
        "reason": message,
      }
  }
  let (first, even) = self.running_options(tree, section)
  {
    "differentFirst": first,
    "differentEven": even,
    "revision": revision,
    "content": Json(
      running_content(paragraphs, self.running_links(part, paragraphs)),
    ),
    "distance": section
    .bind(id => tree.number(id, "pgMar", kind))
    .map(v => v / 20)
    .unwrap_or(0),
    "shared": shared,
    "reason": if shared {
      "Shared running area requires an explicit unlink operation"
    } else {
      ""
    },
  }
}

///|
/// Replaces running text, links and page fields in one source transaction.
pub fn Session::set_running_area(
  self : Session,
  revision : Int,
  kind : String,
  variant : String,
  content : Array[RunningContent],
  distance : Double,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let content = normalize_running_content(content)
  guard distance >= 0 &&
    distance <= 14400 &&
    distance * 20 == (distance * 20).to_int().to_double() else {
    @failure.reject(
      "invalid-operation", "Running distance requires integer twips within the page limit",
    )
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let (section, reference, existing, current) = self.editable_running(
    tree, kind, variant,
  )
  guard !self.running_shared(tree, existing) else {
    @failure.reject(
      "protected-content", "Shared running area requires an explicit unlink operation",
    )
  }
  let current_links = self.running_links(existing, current)
  let same_content = running_content(current, current_links) == content
  let bookmarks = tree.bookmark_targets()
  for item in content {
    if item is Link(_, target) &&
      target.has_prefix("#") &&
      !bookmarks.contains(target[1:].to_owned().to_lower()) {
      @failure.reject(
        "invalid-operation", "Running link requires an available bookmark",
      )
    }
  }
  let old_distance = section
    .bind(id => tree.number(id, "pgMar", kind))
    .map(v => v / 20)
    .unwrap_or(0)
  if same_content &&
    old_distance == distance &&
    !content.any(item => item is Field(_) || item is FormattedField(_, _)) {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = existing.unwrap_or_else(() => {
    self.new_word_part(kind, parts, part_edits, created)
  })
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  parts[part] = document
  let story = WordTree::new(document)
  let relations = Map::from_array(
    self.relationships().filter(r => r.owner == part).map(r => (r.id, r)),
  )
  let addresses = content
    .iter()
    .filter_map(item => {
      if item is Link(_, target) && !target.has_prefix("#") {
        Some(target)
      } else {
        None
      }
    })
    .to_array()
  let relations = self.ensure_hyperlink_relationships(
    part, addresses, relations, parts, part_edits, created,
  )
  let root = story.nodes[0]
  let has_fields = content.any(item => {
    item is Field(_) || item is FormattedField(_, _)
  })
  let content = running_content_markup(
    document, story, current, content, current_links, relations,
  )
  if existing is Some(_) && same_content {
    ()
  } else if existing is Some(_) {
    let change : @xml.SourceChange = if root.empty {
      {
        node: 0,
        offset: root.opening_end - root.start - 2,
        length: 2,
        xml: ">\{content}</\{root.qualified}>",
      }
    } else {
      {
        node: 0,
        offset: root.opening_end - root.start,
        length: root.closing_start - root.opening_end,
        xml: content,
      }
    }
    let (updated, edit) = document.edit_source([change])
    parts[part] = updated
    part_edits.get_or_init(part, () => []).push(edit)
  } else {
    let name = if kind == "header" { "hdr" } else { "ftr" }
    let updated = @xml.Document::parse(
      @utf8.encode("<w:\{name} xmlns:w=\"\{word_uri}\">\{content}</w:\{name}>"),
      part,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[part] = updated
    created[part] = updated
  }
  let (initial, edits, section) = page_section(original, tree, section)
  let mut candidate = initial
  if reference is None {
    let view = { ..self, parts, }
    let relation = view
      .relationships()
      .iter()
      .find_first(rel => {
        rel.owner == self.main &&
        rel.target == part &&
        rel.kind == running_rel_uri + "/" + kind
      })
      .unwrap()
    let tree = WordTree::new(candidate)
    let node = tree.nodes[section]
    let markup = "<w:\{kind}Reference xmlns:w=\"\{word_uri}\" xmlns:r=\"\{running_rel_uri}\" w:type=\"\{variant}\" r:id=\"\{property_attribute(relation.id)}\"/>"
    let previous = tree.children[section]
      .filter(id => {
        tree.nodes[id].name == "headerReference" ||
        (kind == "footer" && tree.nodes[id].name == "footerReference")
      })
      .last()
    let change : @xml.SourceChange = if node.empty {
      {
        node: section,
        offset: node.opening_end - node.start - 2,
        length: 2,
        xml: ">\{markup}</\{node.qualified}>",
      }
    } else {
      {
        node: section,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(node.opening_end) -
        node.start,
        length: 0,
        xml: markup,
      }
    }
    let (updated, edit) = candidate.edit_source([change])
    candidate = updated
    edits.push(edit)
  }
  let tree = WordTree::new(candidate)
  let margin = tree.child(section, "pgMar")
  let values = Map::from_array([
    (kind, Some((distance * 20).to_int().to_string())),
  ])
  let markup = property_markup(tree, candidate, margin, "pgMar", Some(values))
  let change : @xml.SourceChange? = if margin is None {
    let node = tree.nodes[section]
    let earlier = [
      "headerReference", "footerReference", "footnotePr", "endnotePr", "type", "pgSz",
    ]
    let previous = tree.children[section]
      .filter(id => earlier.contains(tree.nodes[id].name))
      .last()
    Some({
      node: section,
      offset: previous.map(id => tree.nodes[id].end).unwrap_or(node.opening_end) -
      node.start,
      length: 0,
      xml: markup,
    })
  } else {
    properties_change(tree, candidate, section, "pgMar", markup)
  }
  if change is Some(change) {
    let (updated, edit) = candidate.edit_source([change])
    candidate = updated
    edits.push(edit)
  }
  self.commit_running(
    candidate,
    edits,
    parts,
    part_edits,
    created,
    probe~,
    profile~,
    images~,
    refresh=if has_fields && (!same_content || old_distance == distance) {
      Some((part, variant))
    } else {
      None
    },
  )
}
