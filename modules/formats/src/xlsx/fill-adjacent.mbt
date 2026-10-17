///|
fn Sheet::fill_row_count(
  self : Sheet,
  row : Int,
  source : Range,
) -> Int raise @failure.Failure {
  let mut count = 0
  for column in source.left..<=source.right {
    let address : Address = { row, column, }
    if self.cells.get(address.name()) is Some(cell) &&
      (cell.value != Blank || cell.formula is Some(_)) {
      count += 1
    }
  }
  count
}

///|
fn fill_edge(values : Array[Int], first : Int, last : Int) -> Bool {
  let index = match values.binary_search(first) {
    Ok(index) | Err(index) => index
  }
  index < values.length() && values[index] <= last
}

///|
fn fill_region(
  source : Range,
  bounds : Range,
  rows : Map[Int, Array[Int]],
  columns : Map[Int, Array[Int]],
) -> Range {
  let mut range = source
  for ;; {
    if range.left > bounds.left &&
      fill_edge(
        columns.get(range.left - 1).unwrap_or([]),
        (range.top - 1).max(bounds.top),
        (range.bottom + 1).min(bounds.bottom),
      ) {
      range = { ..range, left: range.left - 1, }
    } else if range.bottom < bounds.bottom &&
      fill_edge(
        rows.get(range.bottom + 1).unwrap_or([]),
        (range.left - 1).max(bounds.left),
        (range.right + 1).min(bounds.right),
      ) {
      range = { ..range, bottom: range.bottom + 1, }
    } else if range.right < bounds.right &&
      fill_edge(
        columns.get(range.right + 1).unwrap_or([]),
        (range.top - 1).max(bounds.top),
        (range.bottom + 1).min(bounds.bottom),
      ) {
      range = { ..range, right: range.right + 1, }
    } else if range.top > bounds.top &&
      fill_edge(
        rows.get(range.top - 1).unwrap_or([]),
        (range.left - 1).max(bounds.left),
        (range.right + 1).min(bounds.right),
      ) {
      range = { ..range, top: range.top - 1, }
    } else {
      break
    }
  }
  range
}

///|
fn Session::adjacent_fill(
  self : Session,
  index : Int,
  source : Range,
) -> Range raise @failure.Failure {
  let sheet = self.sheets[index]
  let width = source.right - source.left + 1
  guard width.to_int64() * (source.bottom - source.top + 1).to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Fill preview exceeds 4096 cells")
  }
  if source.bottom == 1048576 {
    return source
  }
  let count = sheet.fill_row_count(source.bottom + 1, source)
  if count > 0 {
    if count != width {
      return source
    }
    let mut bottom = source.bottom
    while bottom < 1048576 && sheet.fill_row_count(bottom + 1, source) == width {
      bottom += 1
      guard width.to_int64() * (bottom - source.top + 1).to_int64() <= 4096 else {
        @failure.reject("limit-exceeded", "Fill preview exceeds 4096 cells")
      }
    }
    return { ..source, bottom, }
  }
  let rows : Map[Int, Array[Int]] = Map([])
  let columns : Map[Int, Array[Int]] = Map([])
  for cell in sheet.cells.values() {
    let value = self.calculation
      .bind(c => c.values.get((index, cell.address.name())))
      .unwrap_or(cell.value)
    if value == Blank || value == Text("") {
      continue
    }
    let row = rows.get_or_init(cell.address.row, () => [])
    row.push(cell.address.column)
    let column = columns.get_or_init(cell.address.column, () => [])
    column.push(cell.address.row)
  }
  for values in rows.values() {
    values.sort()
  }
  for values in columns.values() {
    values.sort()
  }
  let book : Range = { top: 1, left: 1, bottom: 1048576, right: 16384, }
  let mut region = fill_region(source, book, rows, columns)
  if read_filter(sheet) is Some(filter) && region.intersects(filter.bounds) {
    let cut = filter.bounds
    for
      bounds in [
        { ..region, right: cut.left - 1, },
        { ..region, left: cut.right + 1, },
        { ..region, bottom: cut.top - 1, },
        { ..region, top: cut.bottom + 1, },
      ] {
      if bounds.covers(source) {
        region = fill_region(source, bounds, rows, columns)
        break
      }
    }
  }
  guard !sheet.merges.any(merge => {
    region.intersects(merge) && !source.covers(merge)
  }) else {
    @failure.reject(
      "protected-content", "Merged regions require merge-aware adjacent fill",
    )
  }
  let mut bottom = region.bottom.max(source.bottom)
  for cell in sheet.cells.values() {
    if cell.address.row > source.bottom &&
      cell.address.row <= bottom &&
      cell.address.column >= source.left &&
      cell.address.column <= source.right &&
      (cell.value != Blank || cell.formula is Some(_)) {
      bottom = cell.address.row - 1
    }
  }
  { ..source, bottom, }
}
