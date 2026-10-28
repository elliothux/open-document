///|
fn axis_markup(
  tree : Tree,
  node : @xml.Node,
  changes : Array[@xml.SourceChange],
) -> String {
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
fn Sheet::axis_cells(
  self : Sheet,
  change : AxisChange,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(self.document)
  let data = tree.nodes[self.data]
  let edits : Array[@xml.SourceChange] = []
  let deleted_rows : Map[Int32, Bool] = Map([])
  let by_node : Map[Int32, Cell] = Map([])
  let by_row : Map[Int32, Array[Cell]] = Map([])
  for cell in self.cells.values() {
    let parent = tree.nodes[cell.node].parent
    by_node[cell.node] = cell
    if by_row.get(parent) is Some(cells) {
      cells.push(cell)
    } else {
      by_row[parent] = [cell]
    }
  }
  for number, id in self.rows {
    let row = tree.nodes[id]
    guard row.attributes.all(a => {
        a.uri.is_empty() &&
        [
          "r", "spans", "s", "customFormat", "ht", "hidden", "customHeight", "outlineLevel",
          "collapsed", "thickTop", "thickBot", "ph",
        ].contains(a.name)
      }) &&
      tree.children
      .get(id)
      .unwrap_or([])
      .all(node => node.uri == spreadsheet_uri && node.name == "c") else {
      @failure.reject(
        "protected-content", "Unknown row metadata prevents structural editing",
      )
    }
    let next = if change.rows {
      change.interval(number, number).map(pair => pair.0)
    } else {
      Some(number)
    }
    if next is Some(number) {
      edits.append(metadata_changes(row, [("r", number.to_string())]))
    } else {
      guard !change.insert else {
        @failure.reject(
          "invalid-operation", "Insertion would discard a worksheet row",
        )
      }
      deleted_rows[id] = true
      edits.push(sheet_node_removal(tree, row))
    }
  }
  for cell in self.cells.values() {
    let node = tree.nodes[cell.node]
    if deleted_rows.contains(node.parent) {
      continue
    }
    guard cell.read_only.is_empty() ||
      cell.read_only == "Rich text cell is read-only" else {
      @failure.reject("protected-content", cell.read_only)
    }
    if change.address(cell.address) is Some(next) {
      edits.append(metadata_changes(node, [("r", next.name())]))
    } else {
      guard !change.insert else {
        @failure.reject(
          "invalid-operation", "Insertion would discard a worksheet cell",
        )
      }
      edits.push(sheet_node_removal(tree, node))
    }
  }
  if !change.rows {
    for id in self.rows.values() {
      if tree.nodes[id].attribute("spans") is Some(_) {
        let columns = by_row
          .get(id)
          .unwrap_or([])
          .filter_map(cell => change.address(cell.address).map(a => a.column))
        columns.sort()
        edits.append(
          metadata_changes(tree.nodes[id], [
            (
              "spans",
              columns.get(0).unwrap_or(1).to_string() +
              ":" +
              columns.last().unwrap_or(1).to_string(),
            ),
          ]),
        )
      }
    }
  }
  if change.insert && change.first > 1 {
    let template = self.cells
      .values()
      .filter(cell => {
        (if change.rows { cell.address.row } else { cell.address.column }) ==
        change.first - 1
      })
      .to_array()
    guard template.length().to_int64() * change.count.to_int64() <=
      (100000 - self.cells.length()).to_int64() else {
      @failure.reject("limit-exceeded", "Inserted formats exceed cell budget")
    }
    let blank = fn(
      address : Address,
      style : Int32,
    ) -> String raise @failure.Failure {
      "<od:c xmlns:od=\"\{spreadsheet_uri}\" r=\"\{address.name()}\" s=\"\{style}\"/>"
    }
    if change.rows {
      let xml = StringBuilder()
      for offset in 0..<change.count {
        let number = change.first + offset
        xml.write_string(
          "<od:row xmlns:od=\"\{spreadsheet_uri}\" r=\"\{number}\"",
        )
        if self.rows.get(change.first - 1) is Some(id) {
          for attribute in tree.nodes[id].attributes {
            if !["r", "spans", "hidden"].contains(attribute.name) {
              xml.write_string(
                " \{attribute.name}=\"\{escaped_attribute(attribute.value)}\"",
              )
            }
          }
        }
        xml.write_string(">")
        let cells = template.copy()
        cells.sort_by((a, b) => a.address.column.compare(b.address.column))
        for cell in cells {
          xml.write_string(blank({ ..cell.address, row: number, }, cell.style))
        }
        xml.write_string("</od:row>")
      }
      let rows = self.rows.keys().to_array()
      rows.sort()
      let next = rows.iter().find_first(number => number >= change.first)
      edits.push(
        if data.empty {
          insertion(data, xml.to_string())
        } else {
          {
            node: data.id,
            offset: next
            .map(number => tree.nodes[self.rows[number]].start)
            .unwrap_or(data.closing_start) -
            data.start,
            length: 0,
            xml: xml.to_string(),
          }
        },
      )
    } else {
      for cell in template {
        let row = tree.nodes[tree.nodes[cell.node].parent]
        let next = tree.children
          .get(row.id)
          .unwrap_or([])
          .iter()
          .find_first(node => {
            by_node
            .get(node.id)
            .map(other => other.address.column >= change.first)
            .unwrap_or(false)
          })
        let xml = StringBuilder()
        for offset in 0..<change.count {
          xml.write_string(
            blank(
              { ..cell.address, column: change.first + offset, },
              cell.style,
            ),
          )
        }
        edits.push({
          node: row.id,
          offset: next.map(node => node.start).unwrap_or(row.closing_start) -
          row.start,
          length: 0,
          xml: xml.to_string(),
        })
      }
    }
  }
  if !change.rows && tree.one(tree.root("worksheet").id, "cols") is Some(cols) {
    let columns = tree.all(cols.id, "col")
    guard cols.attributes.is_empty() &&
      cols.text.trim().is_empty() &&
      tree.children.get(cols.id).unwrap_or([]).length() == columns.length() else {
      @failure.reject(
        "protected-content", "Unknown column container prevents structural rewriting",
      )
    }
    if cols.empty {
      return join_insertions(edits)
    }
    let fragments : Array[(Int32, String)] = []
    let mut inherited : @xml.Node? = None
    for node in columns {
      let first = natural(node.attribute("min").unwrap_or(""), 16384)
      let last = natural(node.attribute("max").unwrap_or(""), 16384)
      if first <= change.first - 1 && change.first - 1 <= last {
        inherited = Some(node)
      }
      if change.insert && first < change.first && change.first <= last {
        fragments.push(
          (first, column_markup(tree, node, first, change.first - 1, [])),
        )
        if change.first + change.count <= change.limit() {
          fragments.push(
            (
              change.first + change.count,
              column_markup(
                tree,
                node,
                change.first + change.count,
                (last + change.count).min(change.limit()),
                [],
              ),
            ),
          )
        }
      } else if change.interval(first, last) is Some((first, last)) {
        fragments.push((first, column_markup(tree, node, first, last, [])))
      }
    }
    if change.insert && inherited is Some(node) {
      let source = axis_markup(
        tree,
        node,
        metadata_changes(node, [
          ("min", change.first.to_string()),
          ("max", (change.first + change.count - 1).to_string()),
          ("hidden", "0"),
          ("bestFit", "0"),
        ]),
      )
      fragments.push((change.first, source))
    }
    guard !self.document.source()[cols.opening_end:cols.closing_start].contains(
        "<!--",
      ) &&
      !self.document.source()[cols.opening_end:cols.closing_start].contains(
        "<?",
      ) else {
      @failure.reject(
        "protected-content", "Column comments prevent structural rewriting",
      )
    }
    fragments.sort_by((a, b) => a.0.compare(b.0))
    edits.push({
      node: cols.id,
      offset: cols.opening_end - cols.start,
      length: cols.closing_start - cols.opening_end,
      xml: fragments.map(pair => pair.1).join(""),
    })
  }
  join_insertions(edits)
}
