///|
fn Sheet::shift_cells(
  self : Sheet,
  change : AxisChange,
  limit : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let (low, high) = change.band.unwrap()
  let tree = Tree::new(self.document)
  let source = self.document.source()
  let rows : Map[Int, Array[(Int, String)]] = Map([])
  let changed : Map[Int, Bool] = Map([])
  let originals : Map[Int, Cell] = Map([])
  let mut added = 0
  let append = fn(
    address : Address,
    xml : String,
    generated : Bool,
  ) raise @failure.Failure {
    if generated {
      guard xml.length() <= limit - added else {
        @failure.reject("limit-exceeded", "Shifted cell source exceeds budget")
      }
      added += xml.length()
    }
    if rows.get(address.row) is Some(cells) {
      cells.push((address.column, xml))
    } else {
      rows[address.row] = [(address.column, xml)]
    }
  }
  for cell in self.cells.values() {
    originals[cell.node] = cell
    let node = tree.nodes[cell.node]
    let next = change.address(cell.address)
    if next == Some(cell.address) {
      append(cell.address, source[node.start:node.end].to_owned(), false)
      continue
    }
    guard cell.read_only.is_empty() ||
      cell.read_only == "Rich text cell is read-only" else {
      @failure.reject("protected-content", cell.read_only)
    }
    changed[cell.address.row] = true
    if next is Some(address) {
      changed[address.row] = true
      append(
        address,
        style_markup(
          tree,
          node,
          changes=metadata_changes(node, [
            ("r", address.name()),
            ("s", cell.style.to_string()),
          ]),
        ),
        true,
      )
    } else {
      guard !change.insert else {
        @failure.reject(
          "invalid-operation", "Insertion would discard a worksheet cell",
        )
      }
    }
  }
  if change.insert {
    guard self.cells.length().to_int64() +
      (high - low + 1).to_int64() * change.count.to_int64() <=
      100000 else {
      @failure.reject(
        "limit-exceeded", "Inserted cell formats exceed the cell budget",
      )
    }
    for other in low..<=high {
      let template = if change.rows {
        { row: (change.first - 1).max(1), column: other, }
      } else {
        { row: other, column: (change.first - 1).max(1), }
      }
      let style = if change.first > 1 { self.style_at(template) } else { 0 }
      for index in change.first..<(change.first + change.count) {
        let address = if change.rows {
          { row: index, column: other, }
        } else {
          { row: other, column: index, }
        }
        append(
          address,
          "<od:c xmlns:od=\"\{spreadsheet_uri}\" r=\"\{address.name()}\" s=\"\{style}\"/>",
          true,
        )
        changed[address.row] = true
      }
    }
  }
  let edits : Array[@xml.SourceChange] = []
  let data = tree.nodes[self.data]
  let empty_content = StringBuilder()
  let numbers = self.rows.keys().to_array()
  numbers.sort()
  let updated = changed.keys().to_array()
  updated.sort()
  for number in updated {
    let cells = rows.get(number).unwrap_or([])
    cells.sort_by((a, b) => a.0.compare(b.0))
    if self.rows.get(number) is Some(id) {
      let row = tree.nodes[id]
      guard tree.children
        .get(id)
        .unwrap_or([])
        .all(n => n.uri == spreadsheet_uri && n.name == "c") &&
        row.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Unknown row content prevents cell shifting",
        )
      }
      let content = StringBuilder()
      let mut next = 0
      let mut cursor = row.opening_end
      for child in tree.all(id, "c") {
        content.write_view(source[cursor:child.start])
        while next < cells.length() &&
              cells[next].0 <= originals[child.id].address.column {
          content.write_string(cells[next].1)
          next += 1
        }
        cursor = child.end
      }
      while next < cells.length() {
        content.write_string(cells[next].1)
        next += 1
      }
      if !row.empty {
        content.write_view(source[cursor:row.closing_start])
      }
      let xml = content.to_string()
      if row.empty {
        if !xml.is_empty() {
          edits.push(insertion(row, xml))
        }
      } else if source[row.opening_end:row.closing_start] != xml {
        edits.push({
          node: id,
          offset: row.opening_end - row.start,
          length: row.closing_start - row.opening_end,
          xml,
        })
      }
      if row.attribute("spans") is Some(_) {
        edits.append(
          metadata_changes(row, [
            (
              "spans",
              cells.get(0).map(c => c.0).unwrap_or(1).to_string() +
              ":" +
              cells.last().map(c => c.0).unwrap_or(1).to_string(),
            ),
          ]),
        )
      }
    } else if !cells.is_empty() {
      let xml = "<od:row xmlns:od=\"\{spreadsheet_uri}\" r=\"\{number}\">" +
        cells.map(c => c.1).join("") +
        "</od:row>"
      let next = numbers.iter().find_first(n => n > number)
      if data.empty {
        empty_content.write_string(xml)
      } else {
        edits.push({
          node: self.data,
          offset: next
          .map(n => tree.nodes[self.rows[n]].start)
          .unwrap_or(data.closing_start) -
          data.start,
          length: 0,
          xml,
        })
      }
    }
  }
  if !empty_content.is_empty() {
    edits.push(insertion(data, empty_content.to_string()))
  }
  join_insertions(edits)
}

///|
fn AxisChange::metadata_range(
  self : AxisChange,
  range : Range,
) -> Range? raise @failure.Failure {
  if self.band is Some((low, high)) {
    let (a, b, last) = if self.rows {
      (range.left, range.right, range.bottom)
    } else {
      (range.top, range.bottom, range.right)
    }
    guard last < self.first || b < low || a > high || (a >= low && b <= high) else {
      @failure.reject(
        "protected-content", "Partially shifted merged or linked ranges require a rectangular result",
      )
    }
  }
  self.range(range)
}

///|
fn AxisChange::dimension_range(self : AxisChange, range : Range) -> Range? {
  guard self.band is Some((low, high)) else { return self.range(range) }
  let (a, b) = if self.rows {
    (range.left, range.right)
  } else {
    (range.top, range.bottom)
  }
  if b < low || a > high {
    return Some(range)
  }
  let middle = if self.rows {
    { ..range, left: a.max(low), right: b.min(high), }
  } else {
    { ..range, top: a.max(low), bottom: b.min(high), }
  }
  let mapped = self.range(middle)
  if a >= low && b <= high {
    return mapped
  }
  Some(
    mapped
    .map(next => {
      top: range.top.min(next.top),
      left: range.left.min(next.left),
      bottom: range.bottom.max(next.bottom),
      right: range.right.max(next.right),
    })
    .unwrap_or(range),
  )
}
