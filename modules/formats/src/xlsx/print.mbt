///|
fn Session::print_sheet(
  self : Session,
  index : Int,
  range : String?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  setup : @layout.PageSetup?,
  work : PrintWork,
) -> PrintedSheet raise @failure.Failure {
  let current = self.sheets[index]
  let sheet = current.id
  try {
    let tree = Tree::new(current.document)
    let nodes = hyperlink_nodes(tree)
    if !nodes.is_empty() {
      let links = self.hyperlink_relations(sheet)
      for node in nodes {
        ignore(Range::parse(node.attribute("ref").unwrap_or("")))
        ignore(hyperlink_target(tree, node, links))
      }
    }
  } catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      @failure.reject("unsupported-print", message, part=sheet)
  }
  let conditional = self.conditional_rules(
    current,
    index,
    self.sheets,
    work.formulas,
  )
  guard conditional.reason.is_empty() else {
    @failure.reject("unsupported-print", conditional.reason, part=sheet)
  }
  let settings = read_print_setup(current)
  let print_range = self.read_print_range(index)
  let header_footer = read_header_footer(current)
  let first_page = print_first_page(current)
  let setup = setup.unwrap_or(settings.page())
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
  let range = range
    .map(Range::parse)
    .unwrap_or(
      if print_range.area.is_empty() {
        current.used()
      } else {
        print_area(print_range.area)
      },
    )
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
  let title_rows = print_title_indices(print_range.rows, dimensions.rows, true)
  let title_columns = print_title_indices(
    print_range.columns,
    dimensions.columns,
    false,
  )
  let visible_rows = rows.length() +
    title_rows.filter(row => row < range.top).length()
  let visible_columns = columns.length() +
    title_columns.filter(column => column < range.left).length()
  guard visible_rows.to_int64() * visible_columns.to_int64() <= 32768L else {
    @failure.reject("limit-exceeded", "Print range exceeds 32768 visible cells")
  }
  let scale = print_scale(
    settings, setup, dimensions, rows, columns, title_rows, title_columns,
  )
  let row_groups = print_groups(
    dimensions.rows,
    rows,
    (setup.height - setup.top - setup.bottom) / scale,
    title_rows,
  )
  let column_groups = print_groups(
    dimensions.columns,
    columns,
    (setup.width - setup.left - setup.right) / scale,
    title_columns,
  )
  work.pages += row_groups.length() * column_groups.length()
  guard work.pages <= 1024 else {
    @failure.reject("limit-exceeded", "Print page count exceeds budget")
  }
  let pages : Array[@layout.PositionedPage] = []
  let page_units : Array[Int] = []
  for cols in column_groups {
    for rows in row_groups {
      let page : PagePaint = {
        width: setup.width,
        height: setup.height,
        fills: [],
        bars: [],
        strokes: [],
        texts: [],
      }
      let row_segments = print_segments(dimensions.rows, rows, title_rows)
      let col_segments = print_segments(dimensions.columns, cols, title_columns)
      let row_count = row_segments.fold(init=0, (sum, part) => {
        sum + part.0.length()
      })
      let col_count = col_segments.fold(init=0, (sum, part) => {
        sum + part.0.length()
      })
      work.cells += row_count.to_int64() * col_count.to_int64()
      guard work.cells <= 32768L else {
        @failure.reject(
          "limit-exceeded", "Printed cells including repeated titles exceed budget",
        )
      }
      guard row_count.to_int64() * col_count.to_int64() <= 4096L else {
        @failure.reject(
          "limit-exceeded", "Printed page including titles exceeds 4096 cells",
        )
      }
      let mut units = 0
      for (rows, y) in row_segments {
        for (cols, x) in col_segments {
          let first_row = rows[0]
          let first_col = cols[0]
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
          let cells = self.paint_cells(
            index,
            dimensions,
            rows,
            cols,
            page,
            setup.left / scale + x - dimensions.columns.position(first_col),
            setup.top / scale + y - dimensions.rows.position(first_row),
            probe,
            profile,
            true,
            (setup.width + setup.left - setup.right) / scale,
            conditional,
            work.formulas,
          )
          for cell in cells {
            if cell is { "display": String(text), .. } {
              units += text.length()
            }
          }
          guard units <= 262144 else {
            @failure.reject(
              "limit-exceeded", "Printed text including titles exceeds page budget",
            )
          }
        }
      }
      let positioned = page.positioned()
      let positioned = if scale == 1 {
        positioned
      } else {
        {
          ..positioned,
          primitives: [
            @layout.Transform({ a: scale, b: 0, c: 0, d: scale, e: 0, f: 0, }),
            ..positioned.primitives,
            @layout.Restore,
          ],
        }
      }
      pages.push(positioned)
      page_units.push(units)
    }
  }
  {
    name: current.name,
    setup,
    scale,
    headers: header_footer,
    first_page,
    pages,
    units: page_units,
  }
}
