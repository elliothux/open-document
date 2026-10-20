///|
fn Sheet::axis_sparklines(
  self : Sheet,
  change : AxisChange,
  target : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let items : Array[Sparkline] = []
  for item in self.sparklines.items {
    let own = self.name.to_lower() == target.to_lower()
    let next = if own { change.address(item.cell) } else { Some(item.cell) }
    guard !change.insert || next is Some(_) else {
      @failure.reject(
        "invalid-operation", "Insertion would discard a sparkline location",
      )
    }
    guard next is Some(cell) else { continue }
    let source = if item.owner.unwrap_or(self.name).to_lower() ==
      target.to_lower() {
      item.source.bind(source => {
        let last = if change.rows { source.bottom } else { source.right }
        let inside = match change.band {
          None => true
          Some((first, last)) =>
            if change.rows {
              source.left >= first && source.right <= last
            } else {
              source.top >= first && source.bottom <= last
            }
        }
        guard !change.insert ||
          !inside ||
          last < change.first ||
          last <= change.limit() - change.count else {
          @failure.reject(
            "invalid-operation", "Insertion would discard a sparkline source",
          )
        }
        change.range(source)
      })
    } else {
      item.source
    }
    if source is Some(range) {
      ignore(sparkline_source(range.name(), self.name))
    }
    items.push({
      ..item,
      cell,
      source,
      owner: if source is None {
        None
      } else {
        item.owner
      },
    })
  }
  self.sparkline_changes(items)
}
