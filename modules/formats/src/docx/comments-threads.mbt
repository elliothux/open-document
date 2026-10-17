///|
let comment_para_uri = "http://schemas.microsoft.com/office/word/2010/wordml"

///|
let comment_extended_uri = "http://schemas.microsoft.com/office/word/2012/wordml"

///|
let comment_extended_kind = "http://schemas.microsoft.com/office/2011/relationships/commentsExtended"

///|
fn comment_para_id(value : String) -> String raise @failure.Failure {
  guard value.length() == 8 &&
    value
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }) else {
    @failure.reject("protected-content", "Invalid comment paragraph identity")
  }
  value.to_upper()
}

///|
fn read_comment_threads(
  entries : Array[DocComment],
  document : @xml.Document,
) -> Array[DocComment] raise @failure.Failure {
  let tree = WordTree::new(document)
  let root = tree.nodes[0]
  guard root.uri == comment_extended_uri &&
    root.name == "commentsEx" &&
    root.attributes.all(comment_root_attribute) &&
    root.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown comment thread root")
  }
  let by_para = Map::from_array(
    entries.filter(e => !e.para.is_empty()).map(e => (e.para, e.key)),
  )
  let metadata : Map[String, (String?, Bool)] = Map([])
  for id in tree.children[0] {
    let n = tree.nodes[id]
    guard n.uri == comment_extended_uri &&
      n.name == "commentEx" &&
      n.text.trim().is_empty() &&
      tree.children[id].is_empty() &&
      n.attributes.all(a => {
        a.uri == comment_extended_uri &&
        ["paraId", "paraIdParent", "done"].contains(a.name)
      }) else {
      @failure.reject("protected-content", "Unknown comment thread metadata")
    }
    let para = comment_para_id(
      n.attribute("paraId", uri=comment_extended_uri).unwrap_or(""),
    )
    guard by_para.contains(para) && !metadata.contains(para) else {
      @failure.reject(
        "protected-content", "Duplicate or detached comment thread identity",
      )
    }
    let parent = n
      .attribute("paraIdParent", uri=comment_extended_uri)
      .map(comment_para_id)
    let done = n.attribute("done", uri=comment_extended_uri).unwrap_or("0")
    guard ["0", "1", "false", "true"].contains(done) else {
      @failure.reject("protected-content", "Invalid comment resolved state")
    }
    metadata[para] = (parent, done == "1" || done == "true")
  }
  entries.map(e => {
    guard metadata.get(e.para) is Some((parent, done)) else { return e }
    let key = if parent is Some(parent) {
      guard by_para.get(parent) is Some(key) &&
        key != e.key &&
        metadata.get(parent).map(p => p.0 is None).unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Detached cyclic or nested comment replies are protected",
        )
      }
      Some(key)
    } else {
      None
    }
    { ..e, parent: key, done, }
  })
}

///|
fn next_comment_para(document : @xml.Document) -> String raise @failure.Failure {
  let used : Map[String, Bool] = Map([])
  for n in document.nodes() {
    if n.uri == word_uri &&
      n.name == "p" &&
      n.attribute("paraId", uri=comment_para_uri) is Some(para) {
      used[comment_para_id(para)] = true
    }
  }
  for i in 1..<=65536 {
    let para = comment_hex(i)
    if !used.contains(para) {
      return para
    }
  }
  @failure.reject("limit-exceeded", "Comment paragraph identities exhausted")
}

///|
fn comment_body_change(node : @xml.Node, body : String) -> @xml.SourceChange {
  if node.empty {
    {
      node: node.id,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{body}</\{node.qualified}>",
    }
  } else {
    {
      node: node.id,
      offset: node.opening_end - node.start,
      length: node.closing_start - node.opening_end,
      xml: body,
    }
  }
}

///|
fn store_comment_edit(
  path : String,
  document : @xml.Document,
  edit : @xml.Edit,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
) -> Unit {
  parts[path] = document
  if created.contains(path) {
    created[path] = document
  } else {
    if !edits.contains(path) {
      edits[path] = []
    }
    edits[path].push(edit)
  }
}

///|
fn comment_thread_markup(
  para : String,
  parent : String?,
  done : Bool,
) -> String {
  let parent = parent.map(p => " od:paraIdParent=\"\{p}\"").unwrap_or("")
  "<od:commentEx xmlns:od=\"\{comment_extended_uri}\" od:paraId=\"\{para}\"\{parent} od:done=\"\{if done { "1" } else { "0" }}\"/>"
}

///|
fn comment_attribute_change(
  tree : WordTree,
  id : Int,
  uri : String,
  name : String,
  value : String,
) -> @xml.SourceChange raise @failure.Failure {
  let node = tree.nodes[id]
  if node.attributes.iter().find_first(a => a.uri == uri && a.name == name)
    is Some(a) {
    return {
      node: id,
      offset: a.start - node.start,
      length: a.end - a.start,
      xml: value,
    }
  }
  let bindings : Map[String, String] = Map([])
  let mut current = id
  while current >= 0 {
    for (prefix, uri) in tree.nodes[current].namespaces {
      if !bindings.contains(prefix) {
        bindings[prefix] = uri
      }
    }
    current = tree.nodes[current].parent
  }
  let found = bindings
    .iter()
    .find_first(p => !p.0.is_empty() && p.1 == uri)
    .map(p => p.0)
  let prefix = if found is Some(prefix) {
    prefix
  } else {
    for i in 1..<=16384 {
      let prefix = "odcp\{i}"
      if !bindings.contains(prefix) {
        break prefix
      }
    } nobreak {
      @failure.reject(
        "limit-exceeded", "Comment namespace identities exhausted",
      )
    }
  }
  let declaration = if found is Some(_) {
    ""
  } else {
    " xmlns:\{prefix}=\"\{uri}\""
  }
  {
    node: id,
    offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
    length: 0,
    xml: "\{declaration} \{prefix}:\{name}=\"\{value}\"",
  }
}

///|
fn Session::ensure_comment_thread(
  self : Session,
  source : CommentsSource,
  root : DocComment,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
) -> (String, String) raise @failure.Failure {
  let mut para = root.para
  if para.is_empty() {
    para = next_comment_para(source.document)
    let node = source.tree.nodes[root.node]
    let change : @xml.SourceChange = if source.tree.children[root.node].last()
      is Some(p) {
      comment_attribute_change(source.tree, p, comment_para_uri, "paraId", para)
    } else {
      comment_body_change(node, comment_body(None, None, "", para~))
    }
    let (next, edit) = source.document.edit_source([change])
    store_comment_edit(source.part, next, edit, parts, created, edits)
  }
  add_comment_identity(source, para, None, parts, created, edits)
  let markup = comment_thread_markup(para, None, root.done)
  let path = if source.extended is Some((path, document)) {
    let tree = WordTree::new(document)
    if !tree.children[0].any(id => {
        tree.nodes[id]
        .attribute("paraId", uri=comment_extended_uri)
        .map(comment_para_id) ==
        Some(para)
      }) {
      let (next, edit) = append_part_xml(document, markup)
      store_comment_edit(path, next, edit, parts, created, edits)
    }
    path
  } else {
    self.create_comments_part(markup, parts, created, edits, extended=true)
  }
  (para, path)
}
