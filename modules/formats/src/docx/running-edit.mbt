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
  let units = paragraphs
    .iter()
    .fold(init=0, (total, p) => {
      total +
      p.spans.iter().fold(init=0, (units, span) => units + span.text.length())
    }) +
    (paragraphs.length() - 1).max(0)
  guard units <= 8192 else {
    @failure.reject(
      "protected-content", "Header or footer exceeds the plain-text editing limit",
    )
  }
  guard diagnostics.is_empty() else {
    @failure.reject("protected-content", diagnostics[0])
  }
  (section, reference, part, paragraphs)
}

///|
/// Reads a plain-text view of one single-section running area variant.
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
  let (section, _, _, paragraphs) = try {
    let (_, _, part) = self.running_target(tree, kind, variant)
    shared = self.running_shared(tree, part)
    self.editable_running(tree, kind, variant)
  } catch {
    @failure.Failure(message~, ..) =>
      return {
        "revision": revision,
        "text": "",
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
    "text": paragraphs
    .map(p => {
      p.spans.map(s => s.text).join("").replace_all(old="\n", new="\u2028")
    })
    .join("\n"),
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
/// Replaces plain text, preserving paragraph properties and the first run's formatting.
pub fn Session::set_running_area(
  self : Session,
  revision : Int,
  kind : String,
  variant : String,
  text : String,
  distance : Double,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard text.length() <= 8192 &&
    !text.contains("\r") &&
    !text.contains("\u000c") &&
    distance >= 0 &&
    distance <= 14400 &&
    distance * 20 == (distance * 20).to_int().to_double() else {
    @failure.reject(
      "invalid-operation", "Running text requires at most 8192 characters and a distance in integer twips",
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
  let query = self.running_area(revision, kind, variant)
  let same_text = query is { "text": String(old), .. } && old == text
  if query is { "text": String(old), "distance": Number(value, ..), .. } &&
    old == text &&
    value == distance {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = existing.unwrap_or_else(() => {
    self.new_word_part(kind, parts, part_edits, created)
  })
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let story = WordTree::new(document)
  let root = story.nodes[0]
  let paragraphs = story.children[0]
  let content = text
    .split("\n")
    .to_array()
    .mapi((index, value) => {
      if current.get(index) is Some(paragraph) &&
        paragraph.spans
        .map(span => span.text)
        .join("")
        .replace_all(old="\n", new="\u2028") ==
        value.to_owned() {
        let node = story.nodes[paragraphs[index]]
        return document.source()[node.start:node.end].to_owned()
      }
      let template = match paragraphs.get(index) {
        Some(id) => Some(id)
        None => paragraphs.last()
      }
      let ppr = template
        .bind(id => story.child(id, "pPr"))
        .map(id => story.standalone_markup(document, id))
        .unwrap_or("")
      let rpr = template
        .bind(id => story.paragraph_runs(id).get(0))
        .bind(id => story.child(id, "rPr"))
        .map(id => story.standalone_markup(document, id))
        .unwrap_or("")
      "<w:p xmlns:w=\"\{word_uri}\">\{ppr}<w:r>\{rpr}\{inline_markup(value.to_owned(), history_byte_limit / 2)}</w:r></w:p>"
    })
    .join("")
  if existing is Some(_) && same_text {
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
    part_edits[part] = [edit]
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
  )
}
