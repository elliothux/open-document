///|
fn Dependency::formulas(
  self : Dependency,
  index : Map[Int32, Array[(Address, Int32)]],
  work : FormulaWork,
) -> Array[Address] raise @failure.Failure {
  guard index.get(self.sheet) is Some(cells) else { return [] }
  let first = (self.range.top, self.range.left)
  let last = (self.range.bottom, self.range.right)
  let start = for low = 0, high = cells.length() {
    if low == high {
      break low
    }
    let middle = low + (high - low) / 2
    let address = cells[middle].0
    if (address.row, address.column).compare(first) < 0 {
      continue middle + 1, high
    }
    continue low, middle
  }
  let matched : Array[(Address, Int32)] = []
  for i in start..<cells.length() {
    let entry = cells[i]
    if (entry.0.row, entry.0.column).compare(last) > 0 {
      break
    }
    work.spend()
    if entry.0.column >= self.range.left && entry.0.column <= self.range.right {
      matched.push(entry)
    }
  }
  // Dependency order determines which cells consume each volatile value.
  matched.sort_by((a, b) => a.1.compare(b.1))
  matched.map(entry => entry.0)
}

///|
priv struct FormulaChanges {
  cells : Map[Int32, @sorted_set.SortedSet[(Int32, Int32)]]
  ranges : Map[Int32, Array[Range]]
}

///|
fn FormulaChanges::add_cell(
  self : FormulaChanges,
  sheet : Int32,
  row : Int32,
  column : Int32,
) -> Unit {
  match self.cells.get(sheet) {
    Some(cells) => cells.add((row, column))
    None => self.cells[sheet] = @sorted_set.from_array([(row, column)])
  }
}

///|
fn FormulaChanges::new(changed : Array[(Int32, Range)]) -> FormulaChanges {
  let changes = { cells: Map([]), ranges: Map([]), }
  for (sheet, range) in changed {
    if range.top == range.bottom && range.left == range.right {
      changes.add_cell(sheet, range.top, range.left)
    } else {
      match changes.ranges.get(sheet) {
        Some(ranges) => ranges.push(range)
        None => changes.ranges[sheet] = [range]
      }
    }
  }
  changes
}

///|
fn FormulaChanges::intersects(
  self : FormulaChanges,
  sheet : Int32,
  range : Range,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  if self.cells.get(sheet) is Some(cells) {
    for
      (_, column) in cells.range(
        (range.top, range.left),
        (range.bottom, range.right),
      ) {
      work.spend()
      if column >= range.left && column <= range.right {
        return true
      }
    }
  }
  if self.ranges.get(sheet) is Some(ranges) {
    for changed in ranges {
      work.spend()
      if range.intersects(changed) {
        return true
      }
    }
  }
  false
}
