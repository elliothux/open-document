///|
fn print_groups(
  axis : Axis,
  indices : Array[Int],
  available : Double,
) -> Array[Array[Int]] raise @failure.Failure {
  let groups : Array[Array[Int]] = []
  let mut current : Array[Int] = []
  let mut size = 0.0
  for index in indices {
    let next = axis.size(index)
    guard next <= available else {
      @failure.reject(
        "print-overflow", "One row or column exceeds the printable area",
      )
    }
    if !current.is_empty() && size + next > available {
      groups.push(current)
      current = []
      size = 0
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
/// Print at 100%, down each column band before moving right.
pub fn Session::print_layout(
  self : Session,
  revision : Int,
  sheet : String,
  range : String?,
  setup : @layout.PageSetup,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.PositionedDocument raise @failure.Failure {
  self.check_revision(revision)
  guard setup.width >= 36 &&
    setup.width <= 14400 &&
    setup.height >= 36 &&
    setup.height <= 14400 &&
    setup.left >= 0 &&
    setup.right >= 0 &&
    setup.top >= 0 &&
    setup.bottom >= 0 &&
    setup.width - setup.left - setup.right >= 12 &&
    setup.height - setup.top - setup.bottom >= 12 else {
    @failure.reject("invalid-page", "Invalid print paper or margins")
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let range = range.map(Range::parse).unwrap_or(current.used())
  for diagnostic in self.diagnostics {
    if diagnostic.has_prefix("unrendered:" + sheet + ":") {
      @failure.reject(
        "unsupported-print",
        "Unrendered worksheet content: " + diagnostic,
      )
    }
  }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let rows = dimensions.rows.visible(range.top, range.bottom)
  let columns = dimensions.columns.visible(range.left, range.right)
  guard rows.length().to_int64() * columns.length().to_int64() <= 32768L else {
    @failure.reject("limit-exceeded", "Print range exceeds 32768 visible cells")
  }
  let row_groups = print_groups(
    dimensions.rows,
    rows,
    setup.height - setup.top - setup.bottom,
  )
  let column_groups = print_groups(
    dimensions.columns,
    columns,
    setup.width - setup.left - setup.right,
  )
  guard row_groups.length().to_int64() * column_groups.length().to_int64() <=
    1024L else {
    @failure.reject("limit-exceeded", "Print page count exceeds budget")
  }
  let pages : Array[@layout.PositionedPage] = []
  for cols in column_groups {
    for rows in row_groups {
      let page : PagePaint = {
        width: setup.width,
        height: setup.height,
        fills: [],
        strokes: [],
        texts: [],
      }
      if rows is [first_row, ..] && cols is [first_col, ..] {
        let page_range : Range = {
          top: first_row,
          bottom: rows.last().unwrap(),
          left: first_col,
          right: cols.last().unwrap(),
        }
        for merged in current.merges {
          if merged.intersects(page_range) &&
            !(merged.top >= page_range.top &&
            merged.bottom <= page_range.bottom &&
            merged.left >= page_range.left &&
            merged.right <= page_range.right) {
            @failure.reject(
              "print-overflow", "Merged cell crosses a print range or page boundary",
            )
          }
        }
        ignore(
          self.paint_cells(
            index,
            dimensions,
            rows,
            cols,
            page,
            setup.left - dimensions.columns.position(first_col),
            setup.top - dimensions.rows.position(first_row),
            probe,
            profile,
            true,
          ),
        )
      }
      pages.push(page.positioned())
    }
  }
  { pages, fonts: probe.font_info(), }
}
