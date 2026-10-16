///|
fn style_markup(tree : Tree, node : @xml.Node) -> String raise @failure.Failure {
  let ancestors : Array[@xml.Node] = []
  let mut current = node
  while current.parent >= 0 {
    current = tree.nodes[current.parent]
    ancestors.push(current)
  }
  let bindings : Map[String, String] = Map([])
  for ancestor in ancestors.rev() {
    for (prefix, uri) in ancestor.namespaces {
      bindings[prefix] = uri
    }
  }
  let additions = StringBuilder()
  for prefix, uri in bindings {
    if !node.namespaces.any(pair => pair.0 == prefix) {
      additions.write_string(
        " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{escaped_attribute(uri)}\"",
      )
    }
  }
  let source = tree.document.source()
  let offset = node.start + 1 + node.qualified.length()
  source[node.start:offset].to_owned() +
  additions.to_string() +
  source[offset:node.end].to_owned()
}

///|
fn style_fragment(
  tree : Tree,
  node : @xml.Node,
) -> @xml.Document raise @failure.Failure {
  @xml.Document::parse(
    @utf8.encode(style_markup(tree, node)),
    "cell-style",
    128,
    2097152,
  )
}

///|
fn style_children(
  document : @xml.Document,
  values : Array[(String, String)],
) -> @xml.Document raise @failure.Failure {
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  let changes : Array[@xml.SourceChange] = []
  let additions : Map[Int, String] = Map([])
  for (name, markup) in values {
    if tree.one(root.id, name) is Some(child) {
      changes.push({
        node: root.id,
        offset: child.start - root.start,
        length: child.end - child.start,
        xml: markup,
      })
    } else {
      let order = [
        "start", "end", "left", "right", "top", "bottom", "diagonal", "vertical",
        "horizontal",
      ]
      let next = if root.name == "border" {
        tree.children
        .get(root.id)
        .unwrap_or([])
        .iter()
        .find_first(child => {
          order.search(child.name).unwrap_or(100) >
          order.search(name).unwrap_or(100)
        })
      } else {
        None
      }
      let offset = next
        .map(node => node.start - root.start)
        .unwrap_or(root.closing_start - root.start)
      additions[offset] = additions.get(offset).unwrap_or("") + markup
    }
  }
  for offset, markup in additions {
    if markup.is_empty() {
      continue
    }
    changes.push(
      if root.empty {
        insertion(root, markup)
      } else {
        { node: root.id, offset, length: 0, xml: markup, }
      },
    )
  }
  if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
}

///|
fn check_style_fragment(
  document : @xml.Document,
) -> Unit raise @failure.Failure {
  for node in document.nodes() {
    guard node.uri == spreadsheet_uri &&
      node.name != "extLst" &&
      node.attributes.all(a => a.uri.is_empty()) else {
      @failure.reject(
        "protected-content", "Style identity extensions require editing support",
      )
    }
  }
}

///|
priv struct StylePool {
  parent : @xml.Node
  nodes : Array[@xml.Node]
  entries : Array[String]
  indices : Map[String, Int]
  original_count : Int
}

///|
fn style_key(tree : Tree, node : @xml.Node) -> Json {
  let attributes = node.attributes
    .iter()
    .map(attribute => (attribute.uri, attribute.name, attribute.value))
    .collect()
  attributes.sort()
  // Namespace declarations and prefixes do not change a style component's identity.
  Json::array([
    Json(node.uri),
    Json(node.name),
    Json(attributes),
    Json(node.text.trim().to_owned()),
    Json::array(
      tree.children
      .get(node.id)
      .unwrap_or([])
      .map(child => style_key(tree, child)),
    ),
  ])
}

///|
fn StylePool::new(
  tree : Tree,
  name : String,
  child : String,
) -> StylePool raise @failure.Failure {
  let parent = tree
    .one(tree.root("styleSheet").id, name)
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part="",
        offset=-1,
        message="Missing cell style component: " + name,
      ),
    )
  let nodes = tree.all(parent.id, child)
  guard nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Style component count exceeds 4096")
  }
  let entries = nodes.map(node => style_markup(tree, node))
  let indices : Map[String, Int] = Map([])
  for i, node in nodes {
    let key = style_key(tree, node).stringify()
    if !indices.contains(key) {
      indices[key] = i
    }
  }
  { parent, nodes, entries, indices, original_count: entries.length(), }
}

///|
fn StylePool::intern(
  self : StylePool,
  markup : String,
) -> Int raise @failure.Failure {
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    "cell-style",
    128,
    2097152,
  )
  let key = style_key(Tree::new(document), document.nodes()[0]).stringify()
  if self.indices.get(key) is Some(index) {
    return index
  }
  guard self.entries.length() < 4096 else {
    @failure.reject("limit-exceeded", "Style component count exceeds 4096")
  }
  let index = self.entries.length()
  self.entries.push(markup)
  self.indices[key] = index
  index
}

///|
fn StylePool::changes(
  self : StylePool,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if self.entries.length() == self.original_count {
    return []
  }
  [
    ..metadata_changes(self.parent, [
      ("count", self.entries.length().to_string()),
    ]),
    insertion(self.parent, self.entries[self.original_count:].join("")),
  ]
}
