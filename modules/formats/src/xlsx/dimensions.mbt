///|
priv struct AxisSpan {
  first : Int
  last : Int
  size : Double
}

///|
priv struct Axis {
  default_size : Double
  spans : Array[AxisSpan]
  limit : Int
}

///|
priv struct Dimensions {
  rows : Axis
  columns : Axis
  automatic_rows : Map[Int, Bool]
  automatic_columns : Array[(Int, Int)]
}

///|
fn dimension(value : String, max : Double) -> Double raise @failure.Failure {
  let value = number(value)
  guard value >= 0 && value <= max else {
    @failure.reject("malformed-xlsx", "Invalid row or column size")
  }
  value
}

///|
fn read_dimensions(
  tree : Tree,
  root : @xml.Node,
  data : @xml.Node,
) -> Dimensions raise @failure.Failure {
  let format = tree.one(root.id, "sheetFormatPr")
  let row_default = format
    .bind(node => node.attribute("defaultRowHeight"))
    .map(value => dimension(value, 409.5))
    .unwrap_or(15)
  let column_default = format
    .bind(node => node.attribute("defaultColWidth"))
    .map(value => dimension(value, 255))
    .unwrap_or(8.43)
  guard row_default > 0 && column_default > 0 else {
    @failure.reject("malformed-xlsx", "Default dimensions must be positive")
  }
  let rows : Array[AxisSpan] = []
  let automatic_rows : Map[Int, Bool] = Map([])
  let automatic_columns : Array[(Int, Int)] = []
  let custom_height = format
    .map(node => flag(node, "customHeight"))
    .unwrap_or(false)
  let mut previous_row = 0
  for row in tree.all(data.id, "row") {
    let index = natural(
      row.attribute("r").unwrap_or((previous_row + 1).to_string()),
      1048576,
    )
    previous_row = index
    if !flag(row, "customHeight", fallback=custom_height) {
      automatic_rows[index] = row.attribute("ht") is Some(_)
    }
    let height = if flag(row, "hidden") {
      0.0
    } else {
      row
      .attribute("ht")
      .map(value => dimension(value, 409.5))
      .unwrap_or(row_default)
    }
    let default_height = if format
      .map(node => flag(node, "zeroHeight"))
      .unwrap_or(false) {
      0.0
    } else {
      row_default
    }
    if height != default_height {
      rows.push({ first: index, last: index, size: height, })
    }
  }
  rows.sort_by((a, b) => a.first.compare(b.first))
  let columns : Array[AxisSpan] = []
  if tree.one(root.id, "cols") is Some(container) {
    for col in tree.all(container.id, "col") {
      let first = natural(col.attribute("min").unwrap_or(""), 16384)
      let last = natural(col.attribute("max").unwrap_or(""), 16384)
      guard first >= 1 && last >= first && columns.length() < 16384 else {
        @failure.reject("malformed-xlsx", "Invalid column span")
      }
      let size = if flag(col, "hidden") {
        0.0
      } else {
        col
        .attribute("width")
        .map(value => dimension(value, 255))
        .unwrap_or(column_default)
      }
      columns.push({ first, last, size, })
      if flag(col, "bestFit") && !flag(col, "hidden") {
        automatic_columns.push((first, last))
      }
    }
  }
  columns.sort_by((a, b) => a.first.compare(b.first))
  let mut last = 0
  for span in columns {
    guard span.first > last else {
      @failure.reject("malformed-xlsx", "Overlapping column dimensions")
    }
    last = span.last
  }
  {
    automatic_rows,
    automatic_columns,
    rows: {
      default_size: if format
        .map(node => flag(node, "zeroHeight"))
        .unwrap_or(false) {
        0
      } else {
        row_default
      },
      spans: rows,
      limit: 1048576,
    },
    columns: { default_size: column_default, spans: columns, limit: 16384, },
  }
}

///|
fn Axis::size(self : Axis, index : Int) -> Double {
  self.spans
  .iter()
  .find_first(span => span.first <= index && index <= span.last)
  .map(span => span.size)
  .unwrap_or(self.default_size)
}

///|
fn Axis::changed_ranges(self : Axis, other : Axis) -> Array[(Int, Int)] {
  let boundaries : Map[Int, Bool] = Map([(1, true), (self.limit + 1, true)])
  for axis in [self, other] {
    for span in axis.spans {
      boundaries[span.first] = true
      boundaries[span.last + 1] = true
    }
  }
  let points = boundaries.keys().to_array()
  points.sort()
  let changed : Array[(Int, Int)] = []
  let mut a = 0
  let mut b = 0
  for index in 0..<(points.length() - 1) {
    let first = points[index]
    let last = points[index + 1] - 1
    while a < self.spans.length() && self.spans[a].last < first {
      a += 1
    }
    while b < other.spans.length() && other.spans[b].last < first {
      b += 1
    }
    let old = self.spans
      .get(a)
      .filter(span => span.first <= first)
      .map(span => span.size)
      .unwrap_or(self.default_size)
    let new = other.spans
      .get(b)
      .filter(span => span.first <= first)
      .map(span => span.size)
      .unwrap_or(other.default_size)
    if old != new {
      if changed.last() is Some((start, end)) && end + 1 == first {
        changed[changed.length() - 1] = (start, last)
      } else {
        changed.push((first, last))
      }
    }
  }
  changed
}

///|
fn Axis::position(self : Axis, index : Int) -> Double {
  let before = index - 1
  let mut position = before.to_double() * self.default_size
  for span in self.spans {
    if span.first > before {
      break
    }
    position += (before.min(span.last) - span.first + 1).to_double() *
      (span.size - self.default_size)
  }
  position
}

///|
fn Axis::locate(self : Axis, point : Double) -> Int {
  for low = 1, high = self.limit + 1; low < high; {
    let middle = low + (high - low) / 2
    if self.position(middle) + self.size(middle) <= point {
      continue middle + 1, high
    } else {
      continue low, middle
    }
  } nobreak {
    low.min(self.limit)
  }
}

///|
fn Axis::visible(
  self : Axis,
  first : Int,
  last : Int,
) -> Array[Int] raise @failure.Failure {
  let result : Array[Int] = []
  let mut index = first
  while index <= last {
    if self.size(index) > 0 {
      result.push(index)
      index += 1
    } else if self.spans
      .iter()
      .find_first(span => {
        span.first <= index && index <= span.last && span.size == 0
      })
      is Some(span) {
      index = span.last + 1
    } else if self.default_size == 0 {
      index = self.spans
        .iter()
        .filter(span => span.first > index && span.size > 0)
        .map(span => span.first)
        .fold(init=last + 1, (a, b) => a.min(b))
    } else {
      index += 1
    }
    guard result.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Visible axis exceeds budget")
    }
  }
  result
}

///|
fn Dimensions::resolved(
  self : Dimensions,
  digit_width : Double,
  formulas : Bool,
) -> Dimensions {
  // OOXML character width to pixels (maximum digit width), then pixels to points.
  let convert = fn(width : Double) {
    if width == 0 {
      0.0
    } else {
      (
        ((256.0 * width + (128.0 / digit_width).floor()) / 256 * digit_width).floor() +
        5
      ) *
      0.75 *
      (if formulas { 2 } else { 1 })
    }
  }
  {
    ..self,
    rows: self.rows,
    columns: {
      ..self.columns,
      default_size: convert(self.columns.default_size),
      spans: self.columns.spans.map(span => {
        ..span,
        size: convert(span.size),
      }),
    },
  }
}

///|
fn Sheet::used(self : Sheet) -> Range {
  let mut top = 1048576
  let mut left = 16384
  let mut bottom = 1
  let mut right = 1
  for cell in self.cells.values() {
    if cell.value == Blank && cell.formula is None && cell.style == 0 {
      continue
    }
    top = top.min(cell.address.row)
    left = left.min(cell.address.column)
    bottom = bottom.max(cell.address.row)
    right = right.max(cell.address.column)
  }
  for merge in self.merges {
    top = top.min(merge.top)
    left = left.min(merge.left)
    bottom = bottom.max(merge.bottom)
    right = right.max(merge.right)
  }
  for item in self.sparklines.items {
    top = top.min(item.cell.row)
    left = left.min(item.cell.column)
    bottom = bottom.max(item.cell.row)
    right = right.max(item.cell.column)
  }
  { top: top.min(bottom), left: left.min(right), bottom, right, }
}
