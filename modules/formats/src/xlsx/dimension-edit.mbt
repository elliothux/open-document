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
  first : Int,
  last : Int,
  size : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard last - first < 4096 else {
    @failure.reject("limit-exceeded", "Row height edit exceeds 4096 rows")
  }
  let changes : Array[@xml.SourceChange] = []
  let data = tree.nodes[self.data]
  let prefix = data.qualified[:data.qualified.length() - 9].to_owned()
  let insertions : Map[Int, String] = Map([])
  let rows = tree.all(data.id, "row")
  let numbers : Map[Int, Int] = Map([])
  for number, id in self.rows {
    numbers[id] = number
  }
  let ordered = rows.copy()
  ordered.sort_by((a, b) => numbers[a.id].compare(numbers[b.id]))
  let mut next_index = 0
  for number in first..<=last {
    if !self.rows.contains(number) {
      let xml = if size == 0 {
        "<\{prefix}row r=\"\{number}\" hidden=\"1\"/>"
      } else {
        "<\{prefix}row r=\"\{number}\" ht=\"\{size}\" customHeight=\"1\" hidden=\"0\"/>"
      }
      while next_index < ordered.length() &&
            numbers[ordered[next_index].id] <= number {
        next_index += 1
      }
      let next = ordered.get(next_index)
      let offset = next
        .map(row => row.start - data.start)
        .unwrap_or(
          if data.empty {
            data.opening_end - data.start - 2
          } else {
            data.closing_start - data.start
          },
        )
      insertions[offset] = insertions.get(offset).unwrap_or("") + xml
    }
  }
  for row in rows {
    let number = numbers[row.id]
    let values : Array[(String, String)] = []
    if first <= number && number <= last {
      values.append(
        if size == 0 {
          [("hidden", "1")]
        } else {
          [("ht", size.to_string()), ("customHeight", "1"), ("hidden", "0")]
        },
      )
    }
    // Inserting an empty row must not renumber following rows with implicit identities.
    if !insertions.is_empty() && row.attribute("r") is None {
      values.push(("r", number.to_string()))
    }
    changes.append(metadata_changes(row, values))
  }
  for offset, xml in insertions {
    changes.push(
      if data.empty {
        insertion(data, xml)
      } else {
        { node: data.id, offset, length: 0, xml, }
      },
    )
  }
  changes
}

///|
fn resized_column(
  tree : Tree,
  node : @xml.Node,
  first : Int,
  last : Int,
  size : Double?,
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
          ("bestFit", "0"),
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
  size : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let root = tree.root("worksheet")
  let container = tree.one(root.id, "cols")
  let columns = container
    .map(node => tree.all(node.id, "col"))
    .unwrap_or([])
    .map(node => (natural(node.attribute("min").unwrap_or(""), 16384), node))
  columns.sort_by((a, b) => a.0.compare(b.0))
  let prefix = root.qualified[:root.qualified.length() - 9].to_owned()
  let fresh = fn(first : Int, last : Int) {
    if size == 0 {
      "<\{prefix}col min=\"\{first}\" max=\"\{last}\" hidden=\"1\"/>"
    } else {
      "<\{prefix}col min=\"\{first}\" max=\"\{last}\" width=\"\{size}\" customWidth=\"1\" bestFit=\"0\" hidden=\"0\"/>"
    }
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
      output.write_string(fresh(cursor, start - 1))
    }
    if start < first {
      output.write_string(resized_column(tree, node, start, first - 1, None))
    }
    output.write_string(
      resized_column(tree, node, start.max(first), end.min(last), Some(size)),
    )
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
        insertion(container, fresh(cursor, last))
      } else {
        {
          node: root.id,
          offset: tree.nodes[self.data].start - root.start,
          length: 0,
          xml: "<\{prefix}cols>\{fresh(cursor, last)}</\{prefix}cols>",
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
    current.row_height_changes(tree, first, last, size)
  } else {
    current.column_width_changes(tree, first, last, size)
  }
  if changes.is_empty() {
    return self.query()
  }
  let (document, edit) = current.document.edit_source(changes)
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
  let calculation = Calculation::build(sheets, None, [])
  self.commit(
    sheets,
    self.workbook,
    calculation,
    [(current.id, edit)],
    self.selection,
  )
  self.query()
}
