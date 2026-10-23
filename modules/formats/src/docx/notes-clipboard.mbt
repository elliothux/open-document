///|
fn Session::fragment_note(
  self : Session,
  tree : WordTree,
  id : Int,
  limit : Int,
) -> String raise @failure.Failure {
  let node = tree.nodes[id]
  let kind = if node.name == "footnoteReference" {
    "footnote"
  } else {
    "endnote"
  }
  let key = note_key(node.attribute("id", uri=word_uri).unwrap_or(""))
  guard self.note_source(kind) is Some(source) &&
    source.entries.iter().find_first(note => note.key == key) is Some(note) &&
    note.reason.is_empty() &&
    note.paragraph is Some(p) else {
    @failure.reject(
      "protected-content", "Rich note copy requires ordinary note content",
    )
  }
  let styles = self.styles([])
  guard styles.numbering_reference(source.tree, p) is None else {
    @failure.reject(
      "protected-content", "Note lists require copied note numbering",
    )
  }
  let markers : Map[Int, (String, String)] = Map([])
  let objects : Map[Int, String] = Map([])
  for id in source.tree.descendants(p) {
    if source.tree.nodes[id].uri == word_uri &&
      source.tree.nodes[id].name == kind + "Ref" {
      markers[id] = ("", "")
      objects[id] = "<od:\{kind}Ref/>"
    }
  }
  let paragraph = self.paragraph(
    source.tree,
    styles,
    p,
    [],
    running=true,
    note_refs=markers,
  )
  let content = fragment_paragraph(
    source.tree,
    paragraph,
    styles,
    source.document,
    limit,
    Map([]),
    Map([]),
    Map([]),
    Map([]),
    objects,
  )
  let markup = "<odClip:note xmlns:odClip='\{table_fragment_uri}' kind='\{kind}'>\{content}</odClip:note>"
  guard markup.length() <= limit else {
    @failure.reject("limit-exceeded", "Copied note exceeds clipboard budget")
  }
  markup
}

///|
fn Session::import_fragment_notes(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let wrappers = tree.order.filter(id => {
    tree.nodes[id].uri == table_fragment_uri && tree.nodes[id].name == "note"
  })
  guard wrappers.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Copied notes exceed limits")
  }
  let changes : Array[@xml.SourceChange] = []
  for id in wrappers {
    let node = tree.nodes[id]
    let kind = node.attribute("kind").unwrap_or("")
    guard ["footnote", "endnote"].contains(kind) &&
      node.attributes.length() == 1 &&
      node.attributes.all(a => a.uri.is_empty() && a.name == "kind") &&
      node.text.trim().is_empty() &&
      tree.nodes[node.parent].uri == word_uri &&
      tree.nodes[node.parent].name == "r" &&
      tree.nodes[tree.nodes[node.parent].parent].uri == word_uri &&
      tree.nodes[tree.nodes[node.parent].parent].name == "p" &&
      tree.children[id] is [p] &&
      tree.nodes[p].uri == word_uri &&
      tree.nodes[p].name == "p" else {
      @failure.reject(
        "protected-content", "Invalid copied note owner or content",
      )
    }
    let children = tree.descendants(p)
    guard !children.any(child => note_reference(tree.nodes[child])) &&
      children
      .filter(child => {
        tree.nodes[child].uri == word_uri &&
        tree.nodes[child].name == kind + "Ref"
      })
      .length() ==
      1 else {
      @failure.reject(
        "protected-content", "Copied note requires its own marker",
      )
    }
    check_fragment_content(tree, children, Map([]), notes=true)
    let view = { ..self, parts, }
    let key = view.next_note_key(kind)
    let body = tree.standalone_markup(document, p)
    // The same ordinary-note validator protects capture, import and later content edits.
    let check = @xml.Document::parse(
      @utf8.encode(
        "<od:\{kind} xmlns:od='\{word_uri}' od:id='\{key}'>\{body}</od:\{kind}>",
      ),
      "copied-note",
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    guard read_doc_note(WordTree::new(check), 0, kind).reason.is_empty() else {
      @failure.reject(
        "protected-content", "Copied note contains unsupported source",
      )
    }
    self.append_note_source(kind, key, body, parts, edits, created)
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: "<od:\{kind}Reference xmlns:od='\{word_uri}' od:id='\{key}'/>",
    })
  }
  guard tree.order.all(id => !note_reference(tree.nodes[id])) else {
    @failure.reject(
      "protected-content", "Rich note references require copied content",
    )
  }
  if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
}
