///|
priv struct Grid {
  id : Int
  revision : Int
  sheet : String
  key : String
  dimensions : Dimensions
  scroll_x : Double
  scroll_y : Double
  width : Double
  height : Double
  header_width : Double
  header_height : Double
  rtl : Bool
  result : Json
  rows : Array[GridBand]
  columns : Array[GridBand]
}

///|
fn Sheet::cell_range(self : Sheet, address : Address) -> Range {
  self.merges
  .iter()
  .find_first(range => range.contains(address))
  .unwrap_or({
    top: address.row,
    bottom: address.row,
    left: address.column,
    right: address.column,
  })
}

///|
fn place_block(
  page : PagePaint,
  block : @layout.TextBlock,
  rect : @layout.Border,
  horizontal : String,
  vertical : String,
) -> Unit {
  let top = rect.y +
    1.5 +
    (if vertical == "top" {
      0.0
    } else if vertical == "center" {
      (rect.height - 3 - block.height) / 2
    } else {
      rect.height - 3 - block.height
    }).max(0)
  for index, text in block.texts {
    let x = rect.x +
      2.25 +
      (if horizontal == "right" {
        rect.width - 4.5 - block.widths[index]
      } else if horizontal == "center" {
        (rect.width - 4.5 - block.widths[index]) / 2
      } else {
        0.0
      }).max(0)
    page.texts.push(
      (
        {
          ..text,
          runs: text.runs.map(run => {
            ..run,
            x: run.x + x,
            baseline: run.baseline + top,
          }),
        },
        rect,
      ),
    )
  }
}

///|
fn Session::digit_width(
  self : Session,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  guard profile.get(self.normal_font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing font profile mapping: " + self.normal_font,
    )
  }
  let index = probe.font_index(identity)
  let digits = probe.shape("0123456789", self.normal_size, "en", primary=index)
  let mut width = 1.0
  for i in 0..<10 {
    let a = digits.carets
      .iter()
      .find_first(caret => caret.offset == i)
      .map(caret => caret.before)
      .unwrap_or(0)
    let b = digits.carets
      .iter()
      .find_first(caret => caret.offset == i + 1)
      .map(caret => caret.before)
      .unwrap_or(digits.width)
    width = width.max((b - a).abs() / 0.75)
  }
  width.round().max(1)
}

///|
fn Session::resolved_dimensions(
  self : Session,
  sheet : Sheet,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Dimensions raise @failure.Failure {
  sheet.dimensions.resolved(
    self.digit_width(probe, profile),
    sheet.view.formulas,
  )
}

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
  guard rows.length().to_int64() * columns.length().to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Visible cells exceed 4096 cells")
  }
  let sheet = self.sheets[index]
  let (header_width, header_height) = sheet.view.header_size()
  let cells : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for row in rows {
    for column in columns {
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
      let style = conditional.applied(
        self.merged_style(sheet, range),
        address,
        self.sheets,
        index,
        self.calculation.map(c => c.values).unwrap_or(Map([])),
        work,
      )
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
      if !style.fill.is_empty() {
        page.fills.push({
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
          color: style.fill,
        })
      }
      if style.bar is Some(bar) {
        bar.paint(page, rect)
        if !bar.showValue {
          text = ""
        }
      }
      if !printing && sheet.view.grid_lines {
        page.strokes.push((rect, "d9dce1", 0.5))
      }
      for side, edge in style.borders {
        if edge.1 == 0 {
          continue
        }
        let edge_rect : @layout.Border = match side {
          0 => { ..rect, width: 0, }
          1 => { ..rect, x: rect.x + rect.width, width: 0, }
          2 => { ..rect, height: 0, }
          _ => { ..rect, y: rect.y + rect.height, height: 0, }
        }
        page.strokes.push((edge_rect, edge.0, edge.1))
      }
      if !text.is_empty() && rect.width > 4.5 && rect.height > 3 {
        let mut block = probe.text_block(
          text,
          @layout.TextStyle::new(style.font, style.size, style.color),
          profile,
          (rect.width - 4.5).min(14400),
          style.wrap,
        )
        if !sheet.view.formulas &&
          value is Number(_) &&
          !style.wrap &&
          block.widths.any(width => width > rect.width - 4.5) {
          let hash = probe.text_block(
            "#",
            @layout.TextStyle::new(style.font, style.size, style.color),
            profile,
            14400,
            false,
          )
          text = "#".repeat(
            ((rect.width - 4.5) / hash.widths[0].max(0.1))
            .floor()
            .to_int()
            .max(1)
            .min(1024),
          )
          block = probe.text_block(
            text,
            @layout.TextStyle::new(style.font, style.size, style.color),
            profile,
            (rect.width - 4.5).min(14400),
            false,
          )
        }
        let horizontal = if sheet.view.formulas &&
          (style.horizontal == "general" || value is Number(_)) {
          "left"
        } else if style.horizontal != "general" {
          style.horizontal
        } else {
          match value {
            Number(_) => "right"
            Boolean(_) | Error(_) => "center"
            _ => "left"
          }
        }
        place_block(page, block, rect, horizontal, style.vertical)
        if !printing {
          let start = page.texts.length() - block.texts.length()
          let clip : @layout.Border = {
            x: rect.x.max(if sheet.view.rtl { 0 } else { header_width }),
            y: rect.y.max(header_height),
            width: ((rect.x + rect.width).min(
              page.width - (if sheet.view.rtl { header_width } else { 0 }),
            ) -
            rect.x.max(if sheet.view.rtl { 0 } else { header_width })).max(0),
            height: ((rect.y + rect.height).min(page.height) -
            rect.y.max(header_height)).max(0),
          }
          for i in start..<page.texts.length() {
            page.texts[i] = (page.texts[i].0, clip)
          }
        }
      }
      cells.push({
        "cell": sheet.cell_json(
          address,
          self.read_only,
          calculated,
          hide_formula=style.formula_hidden,
          calculation_reason=self.calculation_reason(index, address),
        ),
        "display": text,
        "rect": rect,
        "range": range,
        "diagnostic": style.diagnostic,
      })
    }
  }
  cells
}

///|
pub fn Session::viewport(
  self : Session,
  sheet : String,
  scroll_x : Double,
  scroll_y : Double,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  reveal~ : Bool = false,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  guard width >= 90 &&
    height >= 45 &&
    width <= 14400 &&
    height <= 14400 &&
    scroll_x >= 0 &&
    scroll_x <= 1000000000 &&
    scroll_y >= 0 &&
    scroll_y <= 1000000000 else {
    @failure.reject("invalid-viewport", "Invalid grid viewport")
  }
  let current = self.sheets[index]
  let (header_width, header_height) = current.view.header_size()
  guard current.frozen.layout_reason.is_empty() else {
    @failure.reject("unsupported-view", current.frozen.layout_reason)
  }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let notes : Map[String, CellNote] = Map([])
  let source_notes = self.read_sheet_notes(current) catch {
    @failure.Failure(..) => None
  }
  let mut used = current.used()
  if source_notes is Some(source_notes) {
    for note in source_notes.entries {
      notes[note.address.name()] = note
      used = {
        ..used,
        bottom: used.bottom.max(note.address.row),
        right: used.right.max(note.address.column),
      }
    }
  }
  let extent_row = (used.bottom
  .max(current.frozen.rows + 1)
  .max(if self.selection.0 == sheet { self.selection.1.bottom } else { 1 }) +
  100).min(1048576)
  let extent_column = (used.right
  .max(current.frozen.columns + 1)
  .max(if self.selection.0 == sheet { self.selection.1.right } else { 1 }) +
  20).min(16384)
  let extent_width = dimensions.columns.position(extent_column + 1)
  let extent_height = dimensions.rows.position(extent_row + 1)
  let mut x = scroll_x.min((extent_width - width + header_width).max(0))
  let mut y = scroll_y.min((extent_height - height + header_height).max(0))
  let frozen_width = dimensions.columns.position(current.frozen.columns + 1)
  let frozen_height = dimensions.rows.position(current.frozen.rows + 1)
  if reveal && self.selection.0 == sheet {
    let focus = self.focus
    let left = dimensions.columns.position(focus.column)
    let right = left + dimensions.columns.size(focus.column)
    let top = dimensions.rows.position(focus.row)
    let bottom = top + dimensions.rows.size(focus.row)
    if focus.column > current.frozen.columns &&
      frozen_width < width - header_width {
      if left < x + frozen_width {
        x = (left - frozen_width).max(0)
      } else if right > x + width - header_width {
        x = (right - width + header_width).max(0)
      }
    }
    if focus.row > current.frozen.rows && frozen_height < height - header_height {
      if top < y + frozen_height {
        y = (top - frozen_height).max(0)
      } else if bottom > y + height - header_height {
        y = (bottom - height + header_height).max(0)
      }
    }
  }
  let key = Json::array([
    Json(self.revision),
    Json(sheet),
    Json(x),
    Json(y),
    Json(width),
    Json(height),
    Json(extent_width),
    Json(extent_height),
    Json(profile),
    Json(probe.font_info()),
  ]).stringify()
  if self.grid is Some(grid) && grid.key == key {
    self.font_context = Some((probe, profile.copy()))
    return grid.result
  }
  let rows = dimensions.rows.bands(
    current.frozen.rows,
    y,
    height - header_height,
    extent_row,
  )
  let columns = dimensions.columns.bands(
    current.frozen.columns,
    x,
    width - header_width,
    extent_column,
  )
  let (primitives, cells, row_headers, column_headers, visible_notes) = self.paint_grid(
    index, dimensions, rows, columns, width, height, probe, profile, notes,
  )
  let document : @layout.PositionedDocument = {
    pages: [{ width, height, primitives, }],
    fonts: probe.font_info(),
  }
  guard self.grid_id < 2147483647 else {
    @failure.reject("limit-exceeded", "Grid identity exhausted")
  }
  self.grid_id += 1
  let diagnostics = self.diagnostics.copy()
  for cell in cells {
    if cell is { "diagnostic": String(reason), .. } && !reason.is_empty() {
      let message = "cell-style:" + sheet + ":" + reason
      if !diagnostics.contains(message) {
        diagnostics.push(message)
      }
    }
  }
  let result : Json = {
    "id": self.grid_id,
    "revision": self.revision,
    "sheet": sheet,
    "scrollX": x,
    "scrollY": y,
    "extentWidth": extent_width,
    "extentHeight": extent_height,
    "headerWidth": header_width,
    "headerHeight": header_height,
    "rtl": current.view.rtl,
    "regions": document.drawing(@layout.Images::new()),
    "outlines": probe.outline_resources(),
    "images": [],
    "cells": cells,
    "notes": visible_notes,
    "rows": row_headers,
    "columns": column_headers,
    "diagnostics": diagnostics,
  }
  self.grid = Some({
    id: self.grid_id,
    revision: self.revision,
    sheet,
    key,
    dimensions,
    scroll_x: x,
    scroll_y: y,
    width,
    height,
    header_width,
    header_height,
    rtl: current.view.rtl,
    result,
    rows,
    columns,
  })
  self.font_context = Some((probe, profile.copy()))
  result
}

///|
pub fn Session::hit(
  self : Session,
  id : Int,
  x : Double,
  y : Double,
) -> String raise @failure.Failure {
  self.check()
  guard self.grid is Some(grid) &&
    grid.id == id &&
    grid.revision == self.revision else {
    @failure.reject("stale-layout", "Grid geometry changed")
  }
  guard x >= (if grid.rtl { 0 } else { grid.header_width }) &&
    y >= grid.header_height &&
    x < grid.width - (if grid.rtl { grid.header_width } else { 0 }) &&
    y < grid.height else {
    @failure.reject("invalid-hit", "Point is outside grid cells")
  }
  // Reflection reverses half-open cell boundaries; keep edge hits inside the cell.
  let x = if grid.rtl {
    (grid.width - x - 0.000001).max(grid.header_width)
  } else {
    x
  }
  let address : Address = {
    row: grid.dimensions.rows.locate(
      y -
      grid.header_height +
      grid.rows
      .iter()
      .find_first(band => {
        y >= grid.header_height + band.start &&
        y < grid.header_height + band.start + band.size
      })
      .unwrap().scroll,
    ),
    column: grid.dimensions.columns.locate(
      x -
      grid.header_width +
      grid.columns
      .iter()
      .find_first(band => {
        x >= grid.header_width + band.start &&
        x < grid.header_width + band.start + band.size
      })
      .unwrap().scroll,
    ),
  }
  let range = self.sheets[self.sheet_index(grid.sheet)].cell_range(address)
  let anchor : Address = { row: range.top, column: range.left, }
  anchor.name()
}

///|
pub fn Session::invalidate_geometry(self : Session) -> Unit {
  self.grid = None
}

///|
pub fn Session::selection_geometry(
  self : Session,
  id : Int,
) -> Json raise @failure.Failure {
  self.check()
  guard self.grid is Some(grid) &&
    grid.id == id &&
    grid.revision == self.revision &&
    grid.sheet == self.selection.0 else {
    @failure.reject("stale-layout", "Selection requires current grid geometry")
  }
  let range = self.selection.1
  let first = self.sheets[self.sheet_index(grid.sheet)].cell_range({
    row: range.top,
    column: range.left,
  })
  let last = self.sheets[self.sheet_index(grid.sheet)].cell_range({
    row: range.bottom,
    column: range.right,
  })
  grid.range_geometry(
    {
      top: first.top,
      left: first.left,
      bottom: last.bottom,
      right: last.right,
    },
    self.sheets[self.sheet_index(grid.sheet)].frozen,
  )
}

///|
pub fn Session::navigate(
  self : Session,
  revision : Int,
  direction : String,
  extend_selection : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let sheet = self.sheets[self.sheet_index(self.selection.0)]
  let merged = sheet.cell_range(self.focus)
  let mut focus = self.focus
  let mut step = 1
  match direction {
    "left" => {
      focus = { ..focus, column: merged.left - 1, }
      step = -1
    }
    "right" => focus = { ..focus, column: merged.right + 1, }
    "up" => {
      focus = { ..focus, row: merged.top - 1, }
      step = -1
    }
    "down" => focus = { ..focus, row: merged.bottom + 1, }
    "home" => focus = { ..focus, column: 1, }
    _ =>
      @failure.reject("invalid-operation", "Unknown grid navigation direction")
  }
  let horizontal = ["left", "right", "home"].contains(direction)
  let axis = if horizontal {
    sheet.dimensions.columns
  } else {
    sheet.dimensions.rows
  }
  let mut value = (if horizontal { focus.column } else { focus.row })
    .max(1)
    .min(axis.limit)
  while axis.size(value) == 0 {
    let next = if axis.spans
      .iter()
      .find_first(span => {
        span.first <= value && value <= span.last && span.size == 0
      })
      is Some(span) {
      if step > 0 {
        span.last + 1
      } else {
        span.first - 1
      }
    } else if axis.default_size == 0 {
      axis.spans
      .iter()
      .filter(span => {
        span.size > 0 &&
        (if step > 0 { span.first > value } else { span.last < value })
      })
      .map(span => if step > 0 { span.first } else { span.last })
      .fold(init=if step > 0 { axis.limit + 1 } else { 0 }, (a, b) => {
        if step > 0 {
          a.min(b)
        } else {
          a.max(b)
        }
      })
    } else {
      value + step
    }
    if next < 1 || next > axis.limit {
      return self.query()
    }
    value = next
  }
  focus = if horizontal {
    { ..focus, column: value, }
  } else {
    { ..focus, row: value, }
  }
  let merged = sheet.cell_range(focus)
  focus = { row: merged.top, column: merged.left, }
  let anchor = if extend_selection { self.anchor } else { focus }
  let range : Range = {
    top: anchor.row.min(focus.row),
    bottom: anchor.row.max(focus.row),
    left: anchor.column.min(focus.column),
    right: anchor.column.max(focus.column),
  }
  let result = self.select(revision, sheet.id, range.name())
  self.anchor = anchor
  self.focus = focus
  result
}
