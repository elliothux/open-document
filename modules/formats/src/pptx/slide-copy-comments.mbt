///|
fn Session::copy_slide_comments(
  self : Session,
  tree : Tree,
  target : String,
) -> (@xml.Document, (String, @xml.Document, @xml.Edit)?) raise @failure.Failure {
  let comments = tree.all(tree.root("cmLst").id, "cm", uri=presentation_uri)
  if comments.is_empty() {
    return (
      @xml.Document::parse(
        tree.document.bytes(),
        target,
        self.budget.xml_depth,
        self.budget.entry_bytes,
      ),
      None,
    )
  }
  let links = self.relationships()
  let authors = links
    .iter()
    .filter(link => {
      link.owner == self.main.part &&
      link.kind == relationship_uri + "/commentAuthors"
    })
    .collect()
  guard authors is [link] && !link.external else {
    @failure.reject(
      "protected-content", "Slide comment authors require copying support",
    )
  }
  let original = self.part_document(link.target)
  guard original.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Copied comment authors exceed history budget",
    )
  }
  let author_tree = Tree::new(link.target, original)
  check_slide_copy_markup(author_tree)
  let entries = author_tree.all(
    author_tree.root("cmAuthorLst").id,
    "cmAuthor",
    uri=presentation_uri,
  )
  let authors : Map[String, @xml.Node] = Map([])
  let indices : Map[String, Int64] = Map([])
  for node in entries {
    let id = number(node.attribute("id").unwrap_or(""), 0, 4294967295)
      .to_int64()
      .to_string()
    guard !authors.contains(id) else {
      @failure.reject("malformed-pptx", "Duplicate comment author identity")
    }
    authors[id] = node
    indices[id] = number(node.attribute("lastIdx").unwrap_or(""), 0, 4294967295).to_int64()
  }
  // Imported lastIdx can lag behind comments, so reserve every retained source index.
  for relation in links {
    if relation.kind != relationship_uri + "/comments" || relation.external {
      continue
    }
    let document = self.part_document(relation.target)
    for node in document.nodes() {
      if node.uri != presentation_uri || node.name != "cm" {
        continue
      }
      let id = number(node.attribute("authorId").unwrap_or(""), 0, 4294967295)
        .to_int64()
        .to_string()
      let index = number(node.attribute("idx").unwrap_or(""), 0, 4294967295).to_int64()
      if indices.get(id) is Some(previous) {
        indices[id] = previous.max(index)
      }
    }
  }
  let changes : Array[@xml.SourceChange] = []
  let changed : Map[String, Bool] = Map([])
  for node in comments {
    let id = number(node.attribute("authorId").unwrap_or(""), 0, 4294967295)
      .to_int64()
      .to_string()
    guard indices.get(id) is Some(previous) && previous < 4294967295L else {
      @failure.reject(
        "protected-content", "Comment author or index cannot be copied",
      )
    }
    let next = previous + 1L
    indices[id] = next
    changed[id] = true
    changes.push(attribute_change({ tree, node, }, "idx", next.to_string()))
  }
  let updates = changed
    .keys()
    .map(id => {
      attribute_change(
        { tree: author_tree, node: authors[id], },
        "lastIdx",
        indices[id].to_string(),
      )
    })
    .collect()
  let (updated, edit) = original.edit_source(updates)
  let bytes = tree.document.edit_source(changes).0.bytes()
  (
    @xml.Document::parse(
      bytes,
      target,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    ),
    Some((link.target, updated, edit)),
  )
}
