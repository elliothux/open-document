///|
fn Session::paint_cells(
  self : Session,
  index : Int,
  dimensions : Dimensions,
  rows : Array[Int],
  columns : Array[Int],
  page : PagePaint,
  dx : Double,
  dy : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  printing : Bool,
  mirror_width : Double,
  conditional : ConditionalRules,
  work : FormulaWork,
) -> Array[Json] raise @failure.Failure {
  let indent_unit = self.indent_unit(probe, profile)
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
  let cells : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for row in rows {
    for column in paint_columns[row] {
      let foreign = !requested.contains(column)
      let range = sheet.cell_range({ row, column, })
      let address : Address = { row: range.top, column: range.left, }
      let key = address.name()
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
        calculation.values.get((index, key))
      })
      let value = calculated.unwrap_or(
        cell.map(cell => cell.value).unwrap_or(Blank),
      )
      let missing = cell.bind(cell => cell.formula) is Some(_) && value == Blank
      let mut text = if missing && !sheet.view.formulas {
        "Not calculated"
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
      units += text.length()
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
          width: rect.width,
          height: rect.height,
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
        page.strokes.push((rect, "d9dce1", 0.5))
      }
      for side, edge in style.borders {
        if foreign ||
          edge.style == "none" ||
          !self.border_wins(
            style, address, range, side, rows, columns, conditional, index, work,
          ) {
          continue
        }
        let edge_rect : @layout.Border = match side {
          0 => { ..rect, width: 0, }
          1 => { ..rect, x: rect.x + rect.width, width: 0, }
          2 => { ..rect, height: 0, }
          _ => { ..rect, y: rect.y + rect.height, height: 0, }
        }
        if edge.style == "double" {
          for offset in [-0.75, 0.75] {
            let line = if side < 2 {
              { ..edge_rect, x: edge_rect.x + offset, }
            } else {
              { ..edge_rect, y: edge_rect.y + offset, }
            }
            page.strokes.push((line, edge.color, 0.75))
          }
        } else {
          page.strokes.push((edge_rect, edge.color, edge.width()))
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
        4.5 -
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
        )
        if horizontal == "fill" {
          units += (filled_text_units(block) - text.length()).max(0)
          guard units <= 262144 else {
            @failure.reject(
              "limit-exceeded", "Visible filled text exceeds budget",
            )
          }
        }
        if !sheet.view.formulas &&
          value is Number(_) &&
          !style.wrap &&
          horizontal != "distributed" &&
          horizontal != "fill" &&
          !style.shrink &&
          style.rotation == 0 &&
          block.widths.any(width => width > available) {
          let hash = probe.text_block(
            "#",
            style.text_style(),
            profile,
            14400,
            false,
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
          )
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
      let item : Json = {
        "cell": sheet.cell_json(
          address,
          self.cell_edit_reason(sheet, address),
          calculated,
          hide_formula=style.formula_hidden,
          calculation_reason=self.read_only,
        ),
        "display": text,
        "rect": rect,
        "range": range,
        "diagnostic": style.diagnostic,
      }
      if style.icon is Some(_) && item is Object(fields) {
        fields["accessibleText"] = Json(accessible)
      }
      cells.push(item)
    }
  }
  cells
}
