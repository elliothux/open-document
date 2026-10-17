///|
fn property_markup(
  tree : WordTree,
  document : @xml.Document,
  node : Int?,
  name : String,
  patch : Map[String, String?]?,
) -> String raise @failure.Failure {
  let remove = patch is None
  let patch = patch.unwrap_or(Map([]))
  let values : Map[String, String] = Map([])
  if node is Some(id) {
    for attribute in tree.nodes[id].attributes {
      values[attribute.name] = attribute.value
    }
  }
  let before = values.copy()
  for key, value in patch {
    match value {
      None => values.remove(key)
      Some(value) => values[key] = value
    }
  }
  if node is Some(id) && !remove && before == values {
    let node = tree.nodes[id]
    return document.source()[node.start:node.end].to_owned()
  }
  if node is Some(id) {
    let node = tree.nodes[id]
    let source = document.source()[node.start:node.end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown property markup prevents formatting",
      )
    }
  }
  if remove || values.is_empty() {
    return ""
  }
  let out = StringBuilder()
  out.write_string("<od:\{name} xmlns:od=\"\{word_uri}\"")
  for key, value in values {
    out.write_string(" od:\{key}=\"" + property_attribute(value) + "\"")
  }
  out.write_string("/>")
  out.to_string()
}

///|
fn formatted_properties(
  tree : WordTree,
  document : @xml.Document,
  parent : Int,
  kind : String,
  patch : Map[String, Map[String, String?]?],
  nested~ : Map[String, String] = Map([]),
) -> String raise @failure.Failure {
  let container = tree.child(parent, kind)
  let source = document.source()
  let fields : Map[String, String] = Map([])
  let gaps : Map[String, String] = Map([])
  let mut tail = ""
  let mut changed = false
  if container is Some(id) {
    let node = tree.nodes[id]
    let mut cursor = node.opening_end
    for child in tree.children[id] {
      let item = tree.nodes[child]
      gaps[item.name] = source[cursor:item.start].to_owned()
      fields[item.name] = if nested.get(item.name) is Some(markup) {
        changed = changed || markup != source[item.start:item.end].to_owned()
        markup
      } else if patch.get(item.name) is Some(value) {
        let markup = property_markup(
          tree,
          document,
          Some(child),
          item.name,
          value,
        )
        changed = changed || markup != source[item.start:item.end].to_owned()
        markup
      } else {
        source[item.start:item.end].to_owned()
      }
      cursor = item.end
    }
    if !node.empty {
      tail = source[cursor:node.closing_start].to_owned()
    }
  }
  for name, value in patch {
    if !fields.contains(name) {
      let markup = property_markup(tree, document, None, name, value)
      changed = changed || !markup.is_empty()
      fields[name] = markup
    }
  }
  for name, markup in nested {
    if !fields.contains(name) {
      fields[name] = markup
      changed = changed || !markup.is_empty()
    }
  }
  if !changed {
    return container
      .map(id => {
        let node = tree.nodes[id]
        source[node.start:node.end].to_owned()
      })
      .unwrap_or("")
  }
  let order = if kind == "rPr" {
    [
      "rStyle", "rFonts", "b", "bCs", "i", "iCs", "strike", "color", "sz", "szCs",
      "highlight", "u", "vertAlign", "lang",
    ]
  } else {
    [
      "pStyle", "pageBreakBefore", "numPr", "tabs", "bidi", "spacing", "ind", "jc",
      "autoSpaceDE", "autoSpaceDN", "outlineLvl", "rPr",
    ]
  }
  let out = StringBuilder()
  for name in order {
    out.write_string(gaps.get(name).unwrap_or(""))
    out.write_string(fields.get(name).unwrap_or(""))
  }
  out.write_string(tail)
  let content = out.to_string()
  if content.is_empty() {
    return ""
  }
  match container {
    None => "<od:\{kind} xmlns:od=\"\{word_uri}\">\{content}</od:\{kind}>"
    Some(id) => {
      let node = tree.nodes[id]
      structure_opening(node) + content + "</\{node.qualified}>"
    }
  }
}

///|
fn properties_change(
  tree : WordTree,
  document : @xml.Document,
  parent : Int,
  kind : String,
  markup : String,
) -> @xml.SourceChange? {
  let node = tree.nodes[parent]
  if tree.child(parent, kind) is Some(id) {
    let old = tree.nodes[id]
    if document.source()[old.start:old.end] == markup {
      return None
    }
    Some({
      node: parent,
      offset: old.start - node.start,
      length: old.end - old.start,
      xml: markup,
    })
  } else if markup.is_empty() {
    None
  } else if node.empty {
    Some({
      node: parent,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{markup}</\{node.qualified}>",
    })
  } else {
    Some({
      node: parent,
      offset: node.opening_end - node.start,
      length: 0,
      xml: markup,
    })
  }
}
