///|
fn Axis::uniform(self : Axis, first : Int, last : Int) -> Double? {
  let size = self.size(first)
  let mut cursor = first
  for span in self.spans {
    if span.last < first {
      continue
    }
    if span.first > last {
      break
    }
    if (span.first > cursor && self.default_size != size) || span.size != size {
      return None
    }
    cursor = span.last + 1
  }
  if cursor <= last && self.default_size != size {
    None
  } else {
    Some(size)
  }
}

///|
fn Session::dimension_reason(self : Session, sheet : Sheet) -> String {
  if !self.read_only.is_empty() {
    self.read_only
  } else if sheet.locked {
    "Worksheet is protected"
  } else {
    ""
  }
}

///|
fn Sheet::row_height_changes(
  self : Sheet,
  tree : Tree,
  sizes : Map[Int, Double],
  best_fit~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let metadata : Map[Int, Array[(String, String)]] = Map([])
  for number, size in sizes {
    let values = if size == 0 {
      [("hidden", "1")]
    } else {
      [
        ("ht", size.to_string()),
        ("customHeight", if best_fit { "0" } else { "1" }),
        ("hidden", "0"),
      ]
    }
    if best_fit {
      values.retain(entry => entry.0 != "hidden")
      if self.dimensions.rows.size(number) == 0 {
        values.push(("hidden", "1"))
      }
    }
    metadata[number] = values
  }
  self.row_metadata_changes(tree, metadata)
}

///|
fn resized_column(
  tree : Tree,
  node : @xml.Node,
  first : Int,
  last : Int,
  size : Double?,
  best_fit~ : Bool = false,
) -> String raise @failure.Failure {
  guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes
    .iter()
    .all(attribute => {
      attribute.uri.is_empty() &&
      [
        "min", "max", "width", "style", "hidden", "bestFit", "customWidth", "phonetic",
        "outlineLevel", "collapsed",
      ].contains(attribute.name)
    }) else {
    @failure.reject(
      "protected-content", "Column extensions require dimension editing support",
    )
  }
  let values = [("min", first.to_string()), ("max", last.to_string())]
  if size is Some(size) {
    values.append(
      if size == 0 {
        [("hidden", "1")]
      } else {
        [
          ("width", size.to_string()),
          ("customWidth", "1"),
          ("bestFit", if best_fit { "1" } else { "0" }),
          ("hidden", "0"),
        ]
      },
    )
  }
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
fn Sheet::column_width_changes(
  self : Sheet,
  tree : Tree,
  first : Int,
  last : Int,
  sizes : Array[AxisSpan],
  best_fit~ : Bool = false,
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
    first : Int,
    last : Int,
    node : @xml.Node?,
  ) raise @failure.Failure {
    if node is Some(original) &&
      !sizes.any(span => span.first <= last && span.last >= first) {
      return tree.document.source()[original.start:original.end].to_owned()
    }
    let output = StringBuilder()
    let mut cursor = first
    for span in sizes {
      let start = span.first.max(first)
      let end = span.last.min(last)
      if start > end {
        continue
      }
      if cursor < start && node is Some(original) {
        output.write_string(
          resized_column(tree, original, cursor, start - 1, None),
        )
      }
      if node is Some(node) {
        output.write_string(
          resized_column(tree, node, start, end, Some(span.size), best_fit~),
        )
      } else if span.size == 0 {
        output.write_string(
          "<\{prefix}col min=\"\{start}\" max=\"\{end}\" hidden=\"1\"/>",
        )
      } else {
        output.write_string(
          "<\{prefix}col min=\"\{start}\" max=\"\{end}\" width=\"\{span.size}\" customWidth=\"1\" bestFit=\"\{if best_fit { "1" } else { "0" }}\" hidden=\"0\"/>",
        )
      }
      cursor = end + 1
    }
    if cursor <= last && node is Some(original) {
      output.write_string(resized_column(tree, original, cursor, last, None))
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
      output.write_string(resized_column(tree, node, start, first - 1, None))
    }
    output.write_string(segment(start.max(first), end.min(last), Some(node)))
    if end > last {
      output.write_string(resized_column(tree, node, last + 1, end, None))
    }
    let parent = container.unwrap()
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
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

///|
fn Session::resize_dimensions(
  self : Session,
  sheet : String,
  first : Int,
  last : Int,
  size : Double,
  rows~ : Bool,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard first >= 1 &&
    last >= first &&
    last <= (if rows { 1048576 } else { 16384 }) &&
    !size.is_nan() &&
    !size.is_inf() &&
    size >= 0 &&
    size <= (if rows { 409.5 } else { 255.0 }) else {
    @failure.reject("invalid-operation", "Invalid row or column dimensions")
  }
  let tree = Tree::new(current.document)
  let changes = if rows {
    guard last - first < 4096 else {
      @failure.reject("limit-exceeded", "Row height edit exceeds 4096 rows")
    }
    let sizes : Map[Int, Double] = Map([])
    for axis in first..<=last {
      sizes[axis] = size
    }
    current.row_height_changes(tree, sizes)
  } else {
    current.column_width_changes(tree, first, last, [{ first, last, size, }])
  }
  let mut document = current.document
  let edits : Array[(String, @xml.Edit)] = []
  if !changes.is_empty() {
    let (next, edit) = document.edit_source(changes)
    document = next
    edits.push((current.id, edit))
  }
  if rows {
    let (next, filter_edits) = self.filter_dimension_changes(
      current, document, first, last, size,
    )
    document = next
    edits.append(filter_edits)
  }
  if document.source() == current.document.source() {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let calculation = Calculation::build(sheets, None, [], self.date1904)
  if calculation.visibility_dependent() {
    edits.append(self.cache_edits(sheets, calculation))
  }
  self.commit(sheets, self.workbook, calculation, edits, self.selection)
  self.query()
}
