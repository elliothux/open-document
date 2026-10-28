///|
fn print_title_size(
  axis : Axis,
  titles : Array[Int32],
  first : Int32,
) -> Double {
  if titles is [start, ..] && start < first {
    axis.position(first.min(titles.last().unwrap() + 1)) - axis.position(start)
  } else {
    0
  }
}

///|
fn print_groups(
  axis : Axis,
  indices : Array[Int32],
  available : Double,
  titles : Array[Int32],
) -> Array[Array[Int32]] raise @failure.Failure {
  let groups : Array[Array[Int32]] = []
  let mut current : Array[Int32] = []
  let mut size = 0.0
  for index in indices {
    let next = axis.size(index)
    if current.is_empty() {
      size = print_title_size(axis, titles, index)
    } else if size + next > available {
      groups.push(current)
      current = []
      size = print_title_size(axis, titles, index)
    }
    guard size + next <= available else {
      @failure.reject(
        "print-overflow", "Print titles and one row or column exceed the printable area",
      )
    }
    current.push(index)
    size += next
  }
  if !current.is_empty() {
    groups.push(current)
  }
  if groups.is_empty() {
    groups.push([])
  }
  groups
}

///|
fn print_segments(
  axis : Axis,
  body : Array[Int32],
  titles : Array[Int32],
) -> Array[(Array[Int32], Double)] {
  guard body is [first, ..] else { return [] }
  let prefix = titles.filter(index => index < first)
  if prefix.is_empty() {
    return [(body, 0)]
  }
  // Adjacent title/body intervals paint together so an intact merged cell stays intact.
  if axis.position(prefix.last().unwrap() + 1) == axis.position(first) {
    return [([..prefix, ..body], 0)]
  }
  [(prefix, 0), (body, print_title_size(axis, titles, first))]
}

///|
fn print_title_indices(
  value : String,
  axis : Axis,
  rows : Bool,
) -> Array[Int32] raise @failure.Failure {
  if value.is_empty() {
    return []
  }
  let (first, last) = print_title(value, rows)
  axis.visible(first, last)
}
