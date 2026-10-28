///|
priv struct Rule {
  x : Double
  y : Double
  right : Double
  bottom : Double
  vertical : Bool
  path : Int32
}

///|
fn rule_segment(
  x : Double,
  y : Double,
  r : Double,
  b : Double,
  path : Int32,
) -> Rule? {
  if (x - r).abs() <= 0.5 && (y - b).abs() > 1 {
    Some({
      x: (x + r) / 2,
      y: y.min(b),
      right: (x + r) / 2,
      bottom: y.max(b),
      vertical: true,
      path,
    })
  } else if (y - b).abs() <= 0.5 && (x - r).abs() > 1 {
    Some({
      x: x.min(r),
      y: (y + b) / 2,
      right: x.max(r),
      bottom: (y + b) / 2,
      vertical: false,
      path,
    })
  } else {
    None
  }
}

///|
fn path_rules(path : PdfExtractedPath, index : Int32) -> Array[Rule] {
  let result : Array[Rule] = []
  let mut point = (0.0, 0.0)
  let mut start = point
  if path.stroke.is_empty() || path.clipped || path.style.strokeAlpha == 0 {
    return result
  }
  for segment in path.path {
    match segment {
      Move(x, y) => {
        point = (x, y)
        start = point
      }
      Line(x, y) => {
        if rule_segment(point.0, point.1, x, y, index) is Some(rule) {
          result.push(rule)
        }
        point = (x, y)
      }
      Close => {
        if rule_segment(point.0, point.1, start.0, start.1, index) is Some(rule) {
          result.push(rule)
        }
        point = start
      }
      _ => return []
    }
  }
  result
}

///|
fn root(parents : Array[Int32], value : Int32) -> Int32 {
  let mut index = value
  while parents[index] != index {
    parents[index] = parents[parents[index]]
    index = parents[index]
  }
  index
}

///|
fn join(parents : Array[Int32], a : Int32, b : Int32) -> Unit {
  let first = root(parents, a)
  let second = root(parents, b)
  if first != second {
    parents[second] = first
  }
}

///|
fn coordinates(values : Array[Double]) -> Array[Double] {
  values.sort()
  let result : Array[Double] = []
  for value in values {
    if result.is_empty() || (value - result[result.length() - 1]).abs() > 0.75 {
      result.push(value)
    }
  }
  result
}

///|
fn covered(
  rules : Array[Rule],
  vertical : Bool,
  axis : Double,
  low : Double,
  high : Double,
) -> Bool {
  let selected = rules.filter(rule => {
    rule.vertical == vertical &&
    ((if vertical { rule.x } else { rule.y }) - axis).abs() <= 0.75
  })
  selected.sort_by((a, b) => {
    if vertical {
      a.y.compare(b.y)
    } else {
      a.x.compare(b.x)
    }
  })
  let mut end = low
  for rule in selected {
    let first = if vertical { rule.y } else { rule.x }
    let last = if vertical { rule.bottom } else { rule.right }
    if first <= end + 0.75 && last >= low {
      end = end.max(last)
    }
  }
  end >= high - 0.75
}

///|
fn table_from_rules(
  rules : Array[Rule],
  lines : Array[PdfReadLine],
  paths : Array[PdfExtractedPath],
) -> PdfReadTable? {
  let xs = coordinates(rules.filter(rule => rule.vertical).map(rule => rule.x))
  let ys = coordinates(rules.filter(rule => !rule.vertical).map(rule => rule.y))
  if xs.length() < 2 ||
    ys.length() < 2 ||
    (xs.length() == 2 && ys.length() == 2) ||
    xs.length() > 64 ||
    ys.length() > 257 ||
    (xs.length() - 1) * (ys.length() - 1) > 4096 {
    return None
  }
  let rows = ys.length() - 1
  let columns = xs.length() - 1
  if !covered(rules, true, xs[0], ys[0], ys[rows]) ||
    !covered(rules, true, xs[columns], ys[0], ys[rows]) ||
    !covered(rules, false, ys[0], xs[0], xs[columns]) ||
    !covered(rules, false, ys[rows], xs[0], xs[columns]) {
    return None
  }
  let owners = Array::makei(rows * columns, index => index)
  for row in 0..<rows {
    for column in 0..<columns {
      let slot = row * columns + column
      if column + 1 < columns &&
        !covered(rules, true, xs[column + 1], ys[row], ys[row + 1]) {
        join(owners, slot, slot + 1)
      }
      if row + 1 < rows &&
        !covered(rules, false, ys[row + 1], xs[column], xs[column + 1]) {
        join(owners, slot, slot + columns)
      }
    }
  }
  let regions : Map[Int32, Array[Int32]] = Map([])
  for slot in 0..<(rows * columns) {
    regions.get_or_init(root(owners, slot), () => []).push(slot)
  }
  let cells : Array[PdfReadCell] = []
  let usedPaths : Array[Int32] = []
  for rule in rules {
    if !usedPaths.contains(rule.path) {
      usedPaths.push(rule.path)
    }
  }
  let mut textCount = 0
  for _, slots in regions {
    let top = slots.iter().fold(init=rows, (a, b) => a.min(b / columns))
    let bottom = slots.iter().fold(init=0, (a, b) => a.max(b / columns))
    let left = slots.iter().fold(init=columns, (a, b) => a.min(b % columns))
    let right = slots.iter().fold(init=0, (a, b) => a.max(b % columns))
    if slots.length() != (bottom - top + 1) * (right - left + 1) {
      return None
    }
    let selected : Array[PdfReadLine] = []
    for line in lines {
      let cx = line.x + line.width / 2
      let cy = line.y + line.height / 2
      if cx >= xs[left] &&
        cx <= xs[right + 1] &&
        cy >= ys[top] &&
        cy <= ys[bottom + 1] {
        if line.rotation.abs() > 0.01 ||
          line.x < xs[left] - 1 ||
          line.y < ys[top] - 1 ||
          line.x + line.width > xs[right + 1] + 1 ||
          line.y + line.height > ys[bottom + 1] + 1 {
          return None
        }
        selected.push(line)
        textCount += read_line_text(line).length()
      }
    }
    let mut fill = "FFFFFF"
    for index, path in paths {
      if !path.fill.is_empty() && path.style.fillAlpha == 1 && !path.clipped {
        let points : Array[Double] = []
        let mut rectangle = true
        for segment in path.path {
          match segment {
            Move(x, y) | Line(x, y) => points.append([x, y])
            Close => ()
            _ => rectangle = false
          }
        }
        if rectangle && points.length() >= 8 {
          let (x, y, r, b) = read_bounds(points)
          if (x - xs[left]).abs() < 0.75 &&
            (r - xs[right + 1]).abs() < 0.75 &&
            (y - ys[top]).abs() < 0.75 &&
            (b - ys[bottom + 1]).abs() < 0.75 {
            fill = path.fill
            if !usedPaths.contains(index) {
              usedPaths.push(index)
            }
          }
        }
      }
    }
    cells.push({
      row: top,
      column: left,
      rowSpan: bottom - top + 1,
      columnSpan: right - left + 1,
      lines: selected,
      fill,
    })
  }
  if textCount == 0 {
    return None
  }
  cells.sort_by((a, b) => {
    if a.row == b.row {
      a.column.compare(b.column)
    } else {
      a.row.compare(b.row)
    }
  })
  Some({ xs, ys, cells, paths: usedPaths, })
}

///|
pub fn read_tables(
  paths : Array[PdfExtractedPath],
  lines : Array[PdfReadLine],
) -> Array[PdfReadTable] raise @failure.Failure {
  let rules : Array[Rule] = []
  for index, path in paths {
    rules.append(path_rules(path, index))
  }
  guard rules.length() <= 2048 else {
    @failure.reject("limit-exceeded", "PDF table detection exceeds line budget")
  }
  let parents = Array::makei(rules.length(), index => index)
  for index, first in rules {
    for secondIndex in (index + 1)..<rules.length() {
      let second = rules[secondIndex]
      if first.x <= second.right + 0.75 &&
        first.right >= second.x - 0.75 &&
        first.y <= second.bottom + 0.75 &&
        first.bottom >= second.y - 0.75 {
        join(parents, index, secondIndex)
      }
    }
  }
  let groups : Map[Int32, Array[Rule]] = Map([])
  for index, rule in rules {
    groups.get_or_init(root(parents, index), () => []).push(rule)
  }
  let result : Array[PdfReadTable] = []
  for _, group in groups {
    if table_from_rules(group, lines, paths) is Some(table) {
      result.push(table)
    }
  }
  result.sort_by((a, b) => {
    if (a.ys[0] - b.ys[0]).abs() < 1 {
      a.xs[0].compare(b.xs[0])
    } else {
      a.ys[0].compare(b.ys[0])
    }
  })
  result
}

///|
pub fn read_line_in_table(line : PdfReadLine, table : PdfReadTable) -> Bool {
  let cx = line.x + line.width / 2
  let cy = line.y + line.height / 2
  cx >= table.xs[0] &&
  cx <= table.xs[table.xs.length() - 1] &&
  cy >= table.ys[0] &&
  cy <= table.ys[table.ys.length() - 1]
}
