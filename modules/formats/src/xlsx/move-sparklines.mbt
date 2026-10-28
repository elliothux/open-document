///|
fn Sparkline::moved(
  self : Sparkline,
  before : String,
  after : String,
  relocation : CellMove,
) -> Sparkline raise @failure.Failure {
  let mut owner = self.owner.unwrap_or(before)
  let source = self.source.map(range => {
    if owner.to_lower() != relocation.source_sheet.to_lower() {
      return range
    }
    if relocation.source.covers(range) {
      owner = relocation.target_sheet
      return relocation.range(range)
    }
    if relocation.source_sheet != relocation.target_sheet ||
      !range.intersects(relocation.source) {
      return range
    }
    let rows = relocation.target.top - relocation.source.top
    let columns = relocation.target.left - relocation.source.left
    let first : Address = { row: range.top, column: range.left, }
    let last : Address = { row: range.bottom, column: range.right, }
    // A partial same-axis endpoint move extends or shrinks the contiguous data source.
    let a = if relocation.source.contains(first) &&
      (
        (range.left == range.right && columns == 0) ||
        (range.top == range.bottom && rows == 0)
      ) {
      relocation.address(first)
    } else {
      first
    }
    let b = if relocation.source.contains(last) &&
      (
        (range.left == range.right && columns == 0) ||
        (range.top == range.bottom && rows == 0)
      ) {
      relocation.address(last)
    } else {
      last
    }
    {
      top: a.row.min(b.row),
      bottom: a.row.max(b.row),
      left: a.column.min(b.column),
      right: a.column.max(b.column),
    }
  })
  if source is Some(range) {
    ignore(sparkline_source(range.name(), after))
  }
  {
    ..self,
    cell: if before == relocation.source_sheet &&
      relocation.source.contains(self.cell) {
      relocation.address(self.cell)
    } else {
      self.cell
    },
    source,
    owner: if source is Some(_) && owner.to_lower() != after.to_lower() {
      Some(owner)
    } else {
      None
    },
  }
}

///|
fn Sheet::move_sparklines(
  self : Sheet,
  document : @xml.Document,
  from : Sheet,
  to : Sheet,
  relocation : CellMove,
  edits : Array[(String, @xml.Edit)],
  strings : Array[(String, Bool)],
  styles : Int32,
) -> @xml.Document raise @failure.Failure {
  let items : Array[Sparkline] = []
  let origins = if self.id == to.id && from.id != to.id {
    [self, from]
  } else {
    [self]
  }
  for origin in origins {
    for item in origin.sparklines.items {
      let moved = origin.id == from.id && relocation.source.contains(item.cell)
      if !moved && origin.id != self.id {
        continue
      }
      if moved && self.id != to.id {
        continue
      }
      if !moved && self.id == to.id && relocation.target.contains(item.cell) {
        continue
      }
      items.push(item.moved(origin.name, self.name, relocation))
    }
  }
  if items.length() == self.sparklines.items.length() &&
    items.all(item => self.sparklines.items.contains(item)) {
    return document
  }
  guard !self.locked else {
    @failure.reject("protected-content", "A dependent sparkline is protected")
  }
  guard items.length() <= 256 else {
    @failure.reject("limit-exceeded", "Moved sparklines exceed 256")
  }
  items.sort_by((a, b) => {
    if a.cell.row == b.cell.row {
      a.cell.column.compare(b.cell.column)
    } else {
      a.cell.row.compare(b.cell.row)
    }
  })
  let candidate = Sheet::read(
    self.id,
    self.name,
    self.state,
    document,
    strings,
    styles,
  )
  guard !items.any(item => {
    candidate.merges.any(range => range.contains(item.cell))
  }) else {
    @failure.reject(
      "protected-content", "Moved sparklines require unmerged cells",
    )
  }
  let candidate = { ..candidate, sparklines: self.sparklines, }
  let (next, edit) = document.edit_source(candidate.sparkline_changes(items))
  edits.push((self.id, edit))
  next
}
