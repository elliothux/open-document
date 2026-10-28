///|
fn column_markup(
  tree : Tree,
  node : @xml.Node,
  first : Int32,
  last : Int32,
  attributes : Array[(String, String)],
) -> String raise @failure.Failure {
  guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      [
        "min", "max", "width", "style", "hidden", "bestFit", "customWidth", "phonetic",
        "outlineLevel", "collapsed",
      ].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Column extensions require metadata editing support",
    )
  }
  let values = [("min", first.to_string()), ("max", last.to_string())]
  values.append(attributes)
  let changes = metadata_changes(node, values)
  changes.sort_by((a, b) => a.offset.compare(b.offset))
  let output = StringBuilder()
  let mut cursor = node.start
  for change in changes {
    output.write_view(tree.document.source()[cursor:node.start + change.offset])
    output.write_string(change.xml)
    cursor = node.start + change.offset + change.length
  }
  output.write_view(tree.document.source()[cursor:node.end])
  output.to_string()
}

///|
fn Sheet::column_metadata_changes(
  self : Sheet,
  tree : Tree,
  first : Int32,
  last : Int32,
  metadata : Array[(Int32, Int32, Array[(String, String)])],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let root = tree.root("worksheet")
  let container = tree.one(root.id, "cols")
  let columns = container
    .map(node => tree.all(node.id, "col"))
    .unwrap_or([])
    .map(node => (natural(node.attribute("min").unwrap_or(""), 16384), node))
  columns.sort_by((a, b) => a.0.compare(b.0))
  let prefix = root.qualified[:root.qualified.length() - 9].to_owned()
  let segment = fn(
    first : Int32,
    last : Int32,
    node : @xml.Node?,
  ) raise @failure.Failure {
    if node is Some(original) &&
      !metadata.any(span => span.0 <= last && span.1 >= first) {
      return tree.document.source()[original.start:original.end].to_owned()
    }
    let output = StringBuilder()
    let mut cursor = first
    for (start, end, attributes) in metadata {
      let start = start.max(first)
      let end = end.min(last)
      if start > end {
        continue
      }
      if cursor < start && node is Some(original) {
        output.write_string(
          column_markup(tree, original, cursor, start - 1, []),
        )
      }
      if node is Some(node) {
        output.write_string(column_markup(tree, node, start, end, attributes))
      } else {
        let attributes = attributes
          .map(pair => " \{pair.0}=\"\{escaped_attribute(pair.1)}\"")
          .join("")
        output.write_string(
          "<\{prefix}col min=\"\{start}\" max=\"\{end}\"\{attributes}/>",
        )
      }
      cursor = end + 1
    }
    if cursor <= last && node is Some(original) {
      output.write_string(column_markup(tree, original, cursor, last, []))
    }
    output.to_string()
  }
  let changes : Array[@xml.SourceChange] = []
  let mut cursor = first
  for (start, node) in columns {
    let end = natural(node.attribute("max").unwrap_or(""), 16384)
    if end < first || start > last {
      continue
    }
    let output = StringBuilder()
    if start > cursor {
      output.write_string(segment(cursor, start - 1, None))
    }
    if start < first {
      output.write_string(column_markup(tree, node, start, first - 1, []))
    }
    output.write_string(segment(start.max(first), end.min(last), Some(node)))
    if end > last {
      output.write_string(column_markup(tree, node, last + 1, end, []))
    }
    changes.push({
      node: container.unwrap().id,
      offset: node.start - container.unwrap().start,
      length: node.end - node.start,
      xml: output.to_string(),
    })
    cursor = end.min(last) + 1
  }
  if cursor <= last {
    changes.push(
      if container is Some(container) {
        insertion(container, segment(cursor, last, None))
      } else {
        {
          node: root.id,
          offset: tree.nodes[self.data].start - root.start,
          length: 0,
          xml: "<\{prefix}cols>\{segment(cursor, last, None)}</\{prefix}cols>",
        }
      },
    )
  }
  changes
}
