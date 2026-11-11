///|
priv struct PaintedCell {
  address : String
  cell : Json
  text : String
  rect : @layout.Border
  range : Range
  diagnostic : String
  accessible : String?
}

///|
fn PaintedCell::viewport_json(
  self : PaintedCell,
  clip : Json,
  compact : Bool,
) -> Json {
  if compact {
    let rect = self.rect
    let range = self.range
    return Json::array([
      self.cell,
      Json(self.text),
      Json((rect.x, rect.y, rect.width, rect.height)),
      if range.top == range.bottom && range.left == range.right {
        Json::null()
      } else {
        Json((range.top, range.left, range.bottom, range.right))
      },
      Json(self.diagnostic),
      clip,
      self.accessible.map(Json::string).unwrap_or(Json::null()),
    ])
  }
  let fields = {
    "cell": self.cell,
    "display": Json(self.text),
    "rect": Json(self.rect),
    "range": Json(self.range),
    "diagnostic": Json(self.diagnostic),
  }
  if self.accessible is Some(text) {
    fields["accessibleText"] = Json(text)
  }
  fields["clip"] = clip
  Json::object(fields)
}

///|
fn Session::paint_cells(
  self : Session,
  index : Int32,
  dimensions : Dimensions,
  rows : Array[Int32],
  columns : Array[Int32],
  page : PagePaint,
  dx : Double,
  dy : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  printing : Bool,
  mirror_width : Double,
  conditional : ConditionalRules,
  work : FormulaWork,
  compact~ : Bool = false,
  overflow_right? : Double,
) -> Array[PaintedCell] raise @failure.Failure {
  let indent_unit = self.indent_unit(probe, profile)
  let digit_unit = self.digit_width(probe, profile) * 0.75
  guard rows.length().to_int64() * columns.length().to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Visible cells exceed 4096 cells")
  }
  let sheet = self.sheets[index]
  let aligned = conditional.alignment_ranges(
    sheet,
    self.styles,
    Map(rows.map(row => (row, true))),
    self.sheets,
    index,
    self.calculation.map(c => c.values).unwrap_or(Map([])),
    work,
  )
  let text_ranges : Map[String, Range] = Map([])
  let paint_columns = Map(rows.map(row => (row, columns.copy())))
  let requested = Map(columns.map(column => (column, true)))
  let mut count = rows.length() * columns.length()
  for range in aligned {
    let address : Address = { row: range.top, column: range.left, }
    text_ranges[address.name()] = range
    if columns is [first, ..] &&
      range.right >= first &&
      range.left <= columns.last().unwrap() &&
      !requested.contains(range.left) &&
      dimensions.columns.size(range.left) > 0 {
      count += 1
      guard count <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Visible cells including aligned text exceed 4096 cells",
        )
      }
      paint_columns[range.top].push(range.left)
    }
  }
  let overflow_sources : Map[(Int32, Int32), Bool] = Map([])
  if !printing &&
    !sheet.view.rtl &&
    !sheet.view.formulas &&
    columns is [first, ..] &&
    first > sheet.frozen.columns + 1 {
    work.spend(amount=sheet.cells.length())
    let preceding : Map[Int32, Cell] = Map([])
    for cell in sheet.cells.values() {
      let row = cell.address.row
      let column = cell.address.column
      if column > sheet.frozen.columns &&
        column < first &&
        paint_columns.contains(row) &&
        cell.blocks_text_overflow() &&
        preceding
        .get(row)
        .map(other => other.address.column < column)
        .unwrap_or(true) {
        preceding[row] = cell
      }
    }
    for row, cell in preceding {
      let column = cell.address.column
      if (cell.value is Text(_) || cell.formula is Some(_)) &&
        dimensions.columns.size(column) > 0 &&
        !paint_columns[row].contains(column) {
        count += 1
        guard count <= 4096 else {
          @failure.reject(
            "limit-exceeded", "Visible cells including overflowing text exceed 4096 cells",
          )
        }
        paint_columns[row].push(column)
        overflow_sources[(row, column)] = true
      }
    }
  }
  let segment = if rows is [first_row, ..] && columns is [first_col, ..] {
    grid_rect(
      {
        x: dimensions.columns.position(first_col) + dx,
        y: dimensions.rows.position(first_row) + dy,
        width: dimensions.columns.position(columns.last().unwrap() + 1) -
        dimensions.columns.position(first_col),
        height: dimensions.rows.position(rows.last().unwrap() + 1) -
        dimensions.rows.position(first_row),
      },
      mirror_width,
      sheet.view.rtl,
    )
  } else {
    @layout.Border::{ x: 0, y: 0, width: 0, height: 0, }
  }
  let rich = self.rich_text_sources(
    sheet,
    rows
    .map(row => {
      paint_columns[row].map(column => {
        let range = sheet.cell_range({ row, column, })
        Address::{ row: range.top, column: range.left, }
      })
    })
    .flatten(),
    work,
  )
  let (header_width, header_height) = sheet.view.header_size()
  let cells : Array[PaintedCell] = []
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  let first_stroke = page.strokes.length()
  let mut right_border = 0.0
  for row in rows {
    for column in paint_columns[row] {
      let foreign = !requested.contains(column)
      let range = sheet.cell_range({ row, column, })
      let address : Address = { row: range.top, column: range.left, }
      let key = address.name()
      let overflow_source = overflow_sources.contains((row, column))
      if seen.contains(key) {
        continue
      }
      seen[key] = true
      let cell = sheet.cells.get(key)
      if printing &&
        cell.map(cell => !cell.calculation_supported).unwrap_or(false) {
        @failure.reject("unsupported-print", "Unsupported cell value: " + key)
      }
      let mut style = conditional.applied(
        self.merged_style(sheet, range),
        address,
        self.sheets,
        index,
        self.calculation.map(c => c.values).unwrap_or(Map([])),
        work,
      )
      let spans = rich
        .get(key)
        .bind(source => {
          Some(rich_layout_spans(source.0, source.1, style, self.theme, work)) catch {
            @failure.Failure(code="limit-exceeded", ..) as error => raise error
            @failure.Failure(message~, ..) => {
              style = { ..style, diagnostic: message, }
              None
            }
          }
        })
      let calculated = self.calculation.bind(calculation => {
        calculation.values.get((index, address))
      })
      let value = calculated.unwrap_or(
        cell.map(cell => cell.value).unwrap_or(Blank),
      )
      let number = if !sheet.view.formulas {
        section_display(value, style.format)
      } else {
        None
      }
      if number.bind(section => section.color) is Some(color) {
        style = { ..style, color, }
      }
      let missing = cell.bind(cell => cell.formula) is Some(_) && value == Blank
      let mut text = if missing && !sheet.view.formulas {
        "Not calculated"
      } else if number is Some(section) {
        section.display()
      } else {
        sheet.view.display(
          cell.bind(cell => cell.formula),
          value,
          style.format,
          self.date1904,
          hidden=sheet.locked && style.formula_hidden,
        )
      }
      let uncalculated = cell.bind(cell => cell.formula) is Some(_) &&
        calculated is None
      let accessible = text
      if printing && (uncalculated || missing || !style.diagnostic.is_empty()) {
        @failure.reject(
          "unsupported-print",
          if uncalculated || missing {
            "Uncalculated formula: " + key
          } else {
            key + ": " + style.diagnostic
          },
        )
      }
      units += text.length() +
        number.map(section => section.spacing_units()).unwrap_or(0)
      guard units <= 262144 else {
        @failure.reject("limit-exceeded", "Visible text exceeds budget")
      }
      let rect = grid_rect(
        {
          x: dimensions.columns.position(range.left) + dx,
          y: dimensions.rows.position(range.top) + dy,
          width: dimensions.columns.position(range.right + 1) -
          dimensions.columns.position(range.left),
          height: dimensions.rows.position(range.bottom + 1) -
          dimensions.rows.position(range.top),
        },
        mirror_width,
        sheet.view.rtl,
      )
      if printing && !foreign {
        page.anchors.push((range, rect))
      }
      if !foreign && !style.fill.is_empty() {
        page.fills.push({
          x: rect.x,
          y: rect.y,
          width: rect.width + 0.75,
          height: rect.height + 0.75,
          color: style.fill,
        })
      }
      if !foreign && style.bar is Some(bar) {
        bar.paint(page, rect)
        if !bar.showValue {
          text = ""
        }
      }
      if !foreign && style.icon is Some(icon) {
        icon.paint(page, rect, sheet.view.rtl)
        if !icon.showValue {
          text = ""
        }
      }
      for sparkline in sheet.sparklines.items {
        if !foreign && sparkline.cell == address {
          self.paint_sparkline(index, sparkline, page, rect, printing)
        }
      }
      if !foreign && !printing && sheet.view.grid_lines {
        // Every gridline must precede explicit edges, including those of neighboring cells.
        page.bars.push(Stroke(rect, "d9dce1", 0.5))
      }
      for side, edge in style.borders {
        if foreign || (edge.style == "none" && !printing) {
          continue
        }
        for
          (piece, edge_rect) in sheet.border_pieces(
            range, rect, side, rows, columns, dimensions, printing, work,
          ) {
          if self.border_line(
              style,
              { row: piece.top, column: piece.left, },
              piece,
              edge_rect,
              side,
              rows,
              columns,
              conditional,
              index,
              work,
              dimensions,
              printing,
            )
            is Some((edge, edge_rect)) {
            edge.paint(edge_rect, page.strokes)
            if printing &&
              side == 1 &&
              (rect.x + rect.width - segment.x - segment.width).abs() < 0.001 {
              right_border = right_border.max(edge.width())
            }
          }
        }
      }
      let horizontal = style.text_alignment(value, sheet.view.formulas)
      let text_rect = if ["centerContinuous", "fill"].contains(horizontal) &&
        text_ranges.get(key) is Some(span) {
        grid_rect(
          {
            x: dimensions.columns.position(span.left) + dx,
            y: dimensions.rows.position(span.top) + dy,
            width: dimensions.columns.position(span.right + 1) -
            dimensions.columns.position(span.left),
            height: rect.height,
          },
          mirror_width,
          sheet.view.rtl,
        )
      } else {
        rect
      }
      let text_rect = if style.icon is Some(_) {
        {
          ..text_rect,
          x: text_rect.x + (if sheet.view.rtl { 0 } else { 16.5 }),
          width: (text_rect.width - 16.5).max(0),
        }
      } else {
        text_rect
      }
      let indent = style.indent.to_double() * indent_unit
      let available = text_rect.width -
        3.75 -
        (if horizontal == "distributed" {
          2 * indent
        } else if (
            style.wrap &&
            !["justify", "centerContinuous", "fill"].contains(horizontal)
          ) ||
          ["left", "right"].contains(horizontal) {
          indent
        } else {
          0.0
        })
      if !text.is_empty() && available > 0 && rect.height > 3 {
        guard !["centerContinuous", "fill"].contains(horizontal) ||
          available <= 14400 else {
          @failure.reject(
            "limit-exceeded", "Aligned cell text exceeds the layout width budget",
          )
        }
        let mut block = style.cell_text_block(
          probe,
          profile,
          text,
          spans,
          available.min(14400),
          justify=horizontal == "justify",
          distributed=horizontal == "distributed",
          fill=horizontal == "fill",
          number~,
        )
        if !sheet.view.formulas &&
          style.format == "General" &&
          style.rotation == 0 &&
          !style.shrink &&
          !style.wrap &&
          !["fill", "distributed"].contains(horizontal) &&
          value is Number(value) {
          let limit = ((text_rect.width - 3.75) / digit_unit)
            .ceil()
            .max(1)
            .min(11)
            .to_int()
          for digits = limit; digits >= 1; digits = digits - 1 {
            let candidate = general_display(value, limit=digits)
            if candidate != text {
              text = candidate
              block = style.cell_text_block(
                probe,
                profile,
                text,
                spans,
                available.min(14400),
                justify=horizontal == "justify",
                distributed=horizontal == "distributed",
                fill=horizontal == "fill",
                number~,
              )
            }
            if block.widths.all(width => width <= available) {
              break
            }
          }
        }
        if horizontal == "fill" ||
          (!sheet.view.formulas && section_format(style.format) is Some(_)) {
          units += (filled_text_units(block) - text.length()).max(0)
          guard units <= 262144 else {
            @failure.reject(
              "limit-exceeded", "Visible filled text exceeds budget",
            )
          }
        }
        if !sheet.view.formulas &&
          value is Number(_) &&
          style.rotation == 0 &&
          (
            number_overflow(value, style.format, self.date1904) ||
            (
              !style.wrap &&
              horizontal != "distributed" &&
              horizontal != "fill" &&
              !style.shrink &&
              block.widths.any(width => width > available)
            )
          ) {
          let previous_units = filled_text_units(block)
          let hash = probe.text_block(
            "#",
            style.text_style(),
            profile,
            14400,
            false,
            cell=true,
          )
          text = "#".repeat(
            (available / hash.widths[0].max(0.1))
            .floor()
            .to_int()
            .max(1)
            .min(1024),
          )
          block = probe.text_block(
            text,
            style.text_style(),
            profile,
            available.min(14400),
            false,
            cell=true,
          )
          units += (text.length() - previous_units).max(0)
          guard units <= 262144 else {
            @failure.reject(
              "limit-exceeded", "Visible overflow text exceeds budget",
            )
          }
        }
        // shortcut: left-aligned LTR text; extend other alignments with native controls.
        let text_rect = if horizontal == "left" &&
          !sheet.view.rtl &&
          !sheet.view.formulas &&
          !style.wrap &&
          !style.shrink &&
          style.rotation == 0 &&
          range.left == range.right &&
          range.top == range.bottom &&
          value is Text(_) &&
          block.widths.any(width => width > available) {
          sheet.extend_text_rect(
            address,
            dimensions.columns,
            text_rect,
            block.widths.fold(init=0.0, Double::max) + 3.75 + indent,
            overflow_right.unwrap_or(
              (segment.x + segment.width).min(page.width),
            ),
            work,
          )
        } else {
          text_rect
        }
        if overflow_source && text_rect.x + text_rect.width <= segment.x {
          continue
        }
        let bounds = place_block(
          page,
          block,
          text_rect,
          if horizontal == "centerContinuous" {
            "center"
          } else {
            horizontal
          },
          style.vertical,
          indent,
          rotation=style.rotation,
          cell=true,
          mirror=if sheet.view.rtl { Some(mirror_width) } else { None },
        )
        if printing {
          for bound in bounds {
            let bound = if ["centerContinuous", "fill"].contains(horizontal) {
              grid_intersection(bound, segment)
            } else {
              bound
            }
            if bound.width > 0 && bound.height > 0 {
              page.cells.push((range, bound))
            }
          }
        }
        if ["centerContinuous", "fill"].contains(horizontal) {
          let start = page.texts.length() - block.lines.length()
          let clip = grid_intersection(text_rect, segment)
          for i in start..<page.texts.length() {
            page.texts[i] = (page.texts[i].0, clip)
          }
        }
        if !printing {
          let start = page.texts.length() - block.lines.length()
          let clip : @layout.Border = {
            x: text_rect.x.max(if sheet.view.rtl { 0 } else { header_width }),
            y: text_rect.y.max(header_height),
            width: ((text_rect.x + text_rect.width).min(
              page.width - (if sheet.view.rtl { header_width } else { 0 }),
            ) -
            text_rect.x.max(if sheet.view.rtl { 0 } else { header_width })).max(
              0,
            ),
            height: ((text_rect.y + text_rect.height).min(page.height) -
            text_rect.y.max(header_height)).max(0),
          }
          for i in start..<page.texts.length() {
            page.texts[i] = (page.texts[i].0, clip)
          }
        }
      }
      if overflow_source {
        continue
      }
      let details = if printing {
        Json::null()
      } else if compact && cell is None && calculated is None {
        Json(
          (
            key,
            address.row,
            address.column,
            sheet.style_at(address),
            self.cell_edit_reason(sheet, address),
          ),
        )
      } else {
        Json(
          sheet.query_cell(
            address,
            self.cell_edit_reason(sheet, address),
            calculated,
            hide_formula=style.formula_hidden,
            calculation_reason=self.cell_calculation_reason(index, address),
          ),
        )
      }
      cells.push({
        address: key,
        cell: details,
        text,
        rect,
        range,
        diagnostic: style.diagnostic,
        accessible: if style.icon is Some(_) {
          Some(accessible)
        } else {
          None
        },
      })
    }
  }
  if printing && page.strokes.length() > first_stroke {
    // Native column bands retain half of an outer border, rounded down in 96dpi pixels.
    let extra = (right_border / 1.5).floor() * 0.75
    page.strokes.insert(
      first_stroke,
      Clip({
        x: segment.x - 1.5,
        y: 0,
        width: segment.width + 1.5 + extra,
        height: page.height,
      }),
    )
    page.strokes.push(Restore)
  }
  cells
}

///|
fn Cell::blocks_text_overflow(self : Cell) -> Bool {
  self.formula is Some(_) || (self.value != Blank && self.value != Text(""))
}

///|
fn Sheet::extend_text_rect(
  self : Sheet,
  address : Address,
  columns : Axis,
  rect : @layout.Border,
  needed : Double,
  limit : Double,
  work : FormulaWork,
) -> @layout.Border raise @failure.Failure {
  let maximum = (limit - rect.x).max(rect.width)
  let mut width = rect.width
  for next in (address.column + 1)..<=columns.limit {
    if width >= needed || width >= maximum {
      break
    }
    work.spend(amount=self.merges.length() + columns.spans.length() + 1)
    let neighbor : Address = { row: address.row, column: next, }
    if self.cells
      .get(neighbor.name())
      .map(Cell::blocks_text_overflow)
      .unwrap_or(false) ||
      self.merges.any(range => range.contains(neighbor)) {
      break
    }
    width = (width + columns.size(next)).min(maximum)
  }
  { ..rect, width, }
}
