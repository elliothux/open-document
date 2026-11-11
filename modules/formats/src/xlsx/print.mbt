///|
fn print_drawing_clip_axis(
  start : Double,
  length : Double,
  scale : Double,
) -> (Double, Double) {
  let pixel_mm = 25.4 / 96
  // Preserve native margin inch-to-mm-to-pixel ordering before endpoint rounding.
  let pixels = start * scale / 72 * 25.4 / pixel_mm
  let first = pixels.trunc()
  let last = (pixels + length * scale / 0.75 + 0.5).trunc()
  let mm = first * pixel_mm
  // Native metafile paths truncate each endpoint to 1e-5 mm independently.
  let left = (mm * 100000).trunc() / 100000 * 72 / 25.4 / scale
  let right = ((mm + (last - first) * pixel_mm) * 100000).trunc() /
    100000 *
    72 /
    25.4 /
    scale
  (left, right - left)
}

///|
fn print_drawing_clip(rect : @layout.Border, scale : Double) -> @layout.Border {
  let (x, width) = print_drawing_clip_axis(rect.x, rect.width, scale)
  let (y, height) = print_drawing_clip_axis(rect.y, rect.height, scale)
  { x, y, width, height, }
}

///|
fn Session::print_sheet(
  self : Session,
  index : Int32,
  range : String?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  setup : @layout.PageSetup?,
  work : PrintWork,
) -> PrintedSheet raise @failure.Failure {
  let current = self.sheets[index]
  if current.is_chart() {
    return self.print_chart_sheet(index, range, probe, profile, setup, work)
  }
  let sheet = current.id
  let mut hyperlinks : Array[(Range, String)] = []
  try {
    let tree = Tree::new(current.document)
    ignore(self.read_sheet_notes(current, allow_threads=true))
    if self.thread_part(sheet, "threadedComment") is Some(_) {
      self.check_thread_fallbacks(current, self.read_sheet_threads(current))
    }
    let nodes = hyperlink_nodes(tree)
    if !nodes.is_empty() {
      let links = self.hyperlink_relations(sheet)
      for node in nodes {
        let range = Range::parse(node.attribute("ref").unwrap_or(""))
        guard !hyperlinks.any(link => link.0.intersects(range)) else {
          @failure.reject(
            "protected-content", "Overlapping printed hyperlinks require ownership support",
          )
        }
        hyperlinks.push((range, hyperlink_target(tree, node, links)))
      }
    }
    hyperlinks = self.with_formula_hyperlinks(
      current,
      hyperlinks,
      work=work.formulas,
    )
  } catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      @failure.reject("unsupported-print", message, part=sheet)
  }
  let conditional = self.read_conditional_rules(index, work.formulas)
  guard conditional.reason.is_empty() else {
    @failure.reject("unsupported-print", conditional.reason, part=sheet)
  }
  let settings = read_print_setup(current)
  let print_range = self.read_print_range(index)
  let header_footer = read_header_footer(current)
  let first_page = print_first_page(current)
  let setup = setup.unwrap_or(settings.page())
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = (self.sheet_objects(current, dimensions) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      @failure.reject("unsupported-print", message, part=sheet)
  }).filter(picture => picture.printable && picture.visible)
  let first_bar3d = for i, picture in objects {
    if picture.chart is Some((_, chart)) && chart.native_bar is Some(_) {
      break i
    }
  } nobreak {
    objects.length()
  }
  validate_print_page(setup)
  let ranges = range
    .map(print_areas)
    .unwrap_or(
      if print_range.area.is_empty() {
        if current.cells.is_empty() && objects.is_empty() {
          []
        } else {
          let used = drawing_used(current.used(), objects, dimensions)
          [{ ..used, top: 1, left: 1, }]
        }
      } else {
        print_areas(print_range.area)
      },
    )
  let tree = Tree::new(current.document)
  for diagnostic in self.diagnostics {
    if conditional.renders(diagnostic, current) ||
      drawing_diagnostic(current, diagnostic) {
      continue
    }
    if tree.one(tree.root("worksheet").id, "extLst") is Some(list) &&
      diagnostic == "unrendered:" + sheet + ":" + list.qualified &&
      (
        self.slicer_extension(current, tree, list) ||
        self.timeline_extension(current, tree, list)
      ) {
      continue
    }
    if diagnostic.has_prefix("unrendered:" + sheet + ":") {
      @failure.reject(
        "unsupported-print",
        "Unrendered worksheet content: " + diagnostic,
      )
    }
  }
  let reason = sparkline_reason(current, self.sheets)
  guard reason.is_empty() else { @failure.reject("unsupported-print", reason) }
  let title_rows = print_title_indices(print_range.rows, dimensions.rows, true)
  let title_columns = print_title_indices(
    print_range.columns,
    dimensions.columns,
    false,
  )
  let bands = ranges.map(range => {
    let rows = dimensions.rows.visible(range.top, range.bottom)
    let columns = dimensions.columns.visible(range.left, range.right)
    let visible_rows = rows.length() +
      title_rows.filter(row => row < range.top).length()
    let visible_columns = columns.length() +
      title_columns.filter(column => column < range.left).length()
    guard visible_rows.to_int64() * visible_columns.to_int64() <= 32768L else {
      @failure.reject(
        "limit-exceeded", "Print range exceeds 32768 visible cells",
      )
    }
    (rows, columns)
  })
  // One sheet scale must satisfy every area, while each area starts a separate page.
  let scale = bands.fold(init=4.0, (scale, band) => {
    scale.min(
      print_scale(
        settings,
        setup,
        dimensions,
        band.0,
        band.1,
        title_rows,
        title_columns,
        self.print_headers(current, band.0.last().unwrap_or(1), probe, profile),
      ),
    )
  })
  let pages : Array[@layout.PositionedPage] = []
  let page_units : Array[Int32] = []
  let printed_cells : Array[PrintedCell] = []
  let page_offset = work.pages
  for (rows, columns) in bands {
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
    // ONLYOFFICE exhausts the horizontal page bands before advancing rows.
    for rows in row_groups {
      for cols in column_groups {
        let page : PagePaint = {
          width: setup.width,
          height: setup.height,
          fills: [],
          bars: [],
          strokes: [],
          texts: [],
          cells: [],
          anchors: [],
        }
        let row_segments = print_segments(dimensions.rows, rows, title_rows)
        let col_segments = print_segments(
          dimensions.columns,
          cols,
          title_columns,
        )
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
        let picture_paint : Array[@layout.PositionedPrimitive] = []
        for (rows, y) in row_segments {
          for (cols, x) in col_segments {
            let first_row = rows[0]
            let first_col = cols[0]
            let offset_x = setup.left / scale +
              x -
              dimensions.columns.position(first_col)
            let offset_y = setup.top / scale +
              y -
              dimensions.rows.position(first_row)
            let clip = grid_rect(
              print_drawing_clip(
                {
                  x: setup.left / scale + x,
                  y: setup.top / scale + y,
                  width: cols.fold(init=0.0, (sum, c) => {
                    sum + dimensions.columns.size(c)
                  }),
                  height: rows.fold(init=0.0, (sum, r) => {
                    sum + dimensions.rows.size(r)
                  }),
                },
                scale,
              ),
              // Native drawing clips quantize logical endpoints before RTL reflection.
              setup.width / scale,
              current.view.rtl,
            )
            for i, picture in objects {
              let inset = 0.75
              let rect = grid_rect(
                {
                  ..picture.rect,
                  x: picture.rect.x + offset_x + inset,
                  y: picture.rect.y + offset_y + inset,
                },
                setup.width / scale,
                current.view.rtl,
              )
              let visible = grid_intersection(picture.paint_bounds(rect), clip)
              if visible.width > 0 && visible.height > 0 {
                guard !picture.chart_pending else {
                  @failure.reject(
                    "unsupported-print",
                    uncalculated_chart_reason,
                    part=sheet,
                  )
                }
                let first = picture_paint.length()
                picture_paint.push(Clip(clip))
                picture.paint(
                  picture_paint,
                  rect,
                  probe,
                  profile,
                  after_bar3d=i > first_bar3d,
                )
                picture_paint.push(Restore)
                work.add_graphics(picture_paint, first)
              }
            }
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
              overflow_right?=if range is None &&
                print_range.area.is_empty() &&
                cols.last() == columns.last() {
                Some((setup.width - setup.right) / scale)
              } else {
                None
              },
            )
            for cell in cells {
              units += cell.text.length()
            }
            guard units <= 262144 else {
              @failure.reject(
                "limit-exceeded", "Printed text including titles exceeds page budget",
              )
            }
          }
        }
        for (range, rect) in page.anchors {
          let key = (sheet, range.top, range.left)
          if !work.destinations.contains(key) &&
            rect.width > 0 &&
            rect.height > 0 {
            work.destinations[key] = @layout.Internal(
              page_offset + pages.length(),
              (rect.x * scale).max(setup.left),
              (rect.y * scale).max(setup.top),
            )
          }
        }
        for (range, rect) in page.cells {
          let x = (rect.x * scale).max(setup.left)
          let y = (rect.y * scale).max(setup.top)
          let width = ((rect.x + rect.width) * scale).min(
              setup.width - setup.right,
            ) -
            x
          let height = ((rect.y + rect.height) * scale).min(
              setup.height - setup.bottom,
            ) -
            y
          if width > 0 && height > 0 {
            printed_cells.push({
              range,
              rect: {
                page: page_offset + pages.length(),
                line: 0,
                x,
                y,
                width,
                height,
              },
            })
          }
        }
        let positioned = page.positioned()
        positioned.primitives.append(picture_paint)
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
  }
  {
    id: sheet,
    name: current.name,
    setup,
    scale,
    headers: header_footer,
    first_page,
    pages,
    units: page_units,
    cells: printed_cells,
    links: hyperlinks,
  }
}
