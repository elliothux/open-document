///|
fn Sheet::row_metadata_changes(
  self : Sheet,
  tree : Tree,
  metadata : Map[Int, Array[(String, String)]],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard metadata.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Row metadata edit exceeds 4096 rows")
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
  let selected = metadata.keys().to_array()
  selected.sort()
  for number in selected {
    if !self.rows.contains(number) {
      let attributes = metadata[number]
        .map(pair => " \{pair.0}=\"\{escaped_attribute(pair.1)}\"")
        .join("")
      let xml = "<\{prefix}row r=\"\{number}\"\{attributes}/>"
      while next_index < ordered.length() &&
            numbers[ordered[next_index].id] <= number {
        next_index += 1
      }
      let offset = ordered
        .get(next_index)
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
    let values = metadata.get(number).unwrap_or([]).copy()
    // Inserted empty rows must not renumber subsequent implicit source rows.
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
