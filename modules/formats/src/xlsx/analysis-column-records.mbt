///|
fn project_analysis_records(
  document : @xml.Document,
  cache : @xml.Document,
  mapping : Array[Int32],
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  pivot_plain_source(document)
  let tree = Tree::new(document)
  let root = tree.root("pivotCacheRecords")
  let rows = tree.all(root.id, "r")
  let width = mapping.fold(init=0, (width, field) => width.max(field + 1))
  guard rows.length().to_int64() * width.to_int64() <= 65536 &&
    rows.length().to_int64() * mapping.length().to_int64() <= 65536 &&
    natural(root.attribute("count").unwrap_or(""), 65536) == rows.length() &&
    natural(cache.nodes()[0].attribute("recordCount").unwrap_or(""), 65536) ==
    rows.length() else {
    @failure.reject(
      "malformed-xlsx", "Analysis record count is inconsistent or exceeds budget",
    )
  }
  let fields = Tree::new(cache).one(0, "cacheFields").unwrap()
  let source = Tree::new(cache)
  let counts = source
    .all(fields.id, "cacheField")
    .map(field => {
      source
      .one(field.id, "sharedItems")
      .map(items => source.children.get(items.id).unwrap_or([]).length())
      .unwrap_or(0)
    })
  for node in document.nodes() {
    conditional_node(
      tree,
      node,
      if node.name == "pivotCacheRecords" {
        ["count"]
      } else if node.name == "r" || node.name == "m" {
        []
      } else {
        ["v"]
      },
      if node.name == "pivotCacheRecords" {
        ["r"]
      } else if node.name == "r" {
        ["x", "n", "s", "b", "e", "m"]
      } else {
        []
      },
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for row in rows {
    let values = tree.children.get(row.id).unwrap_or([])
    guard values.length() == mapping.length() else {
      @failure.reject("malformed-xlsx", "Analysis record width is inconsistent")
    }
    let mut position = 0
    let prefix = row.qualified[:row.qualified.length() - 1].to_owned()
    for field, value in values {
      if value.name == "x" {
        guard counts[field] > 0 else {
          @failure.reject(
            "malformed-xlsx", "Analysis record member index is unavailable",
          )
        }
        ignore(natural(value.attribute("v").unwrap_or(""), counts[field] - 1))
      } else {
        ignore(pivot_cache_value(value))
      }
      if mapping[field] < 0 {
        changes.push(sheet_node_removal(tree, value))
      } else {
        if position < mapping[field] {
          changes.push({
            node: row.id,
            offset: value.start - row.start,
            length: 0,
            xml: "<\{prefix}x v='0'/>".repeat(mapping[field] - position),
          })
        }
        position = mapping[field] + 1
      }
    }
  }
  document.edit_source(changes)
}
