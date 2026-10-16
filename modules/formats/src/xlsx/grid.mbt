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
  result : Json
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
fn Session::resolved_dimensions(
  self : Session,
  sheet : Sheet,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Dimensions raise @failure.Failure {
  let font = self.styles[0]
  guard profile.get(font.font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing font profile mapping: " + font.font,
    )
  }
  let index = probe.font_index(identity)
  let digits = probe.shape("0123456789", font.size, "en", primary=index)
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
  sheet.dimensions.resolved(width.round().max(1))
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
) -> Array[Json] raise @failure.Failure {
  guard rows.length().to_int64() * columns.length().to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "Visible cells exceed 4096 cells")
  }
  let sheet = self.sheets[index]
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
      let style = self.styles[sheet.style_at(address)]
      let value = self.calculation
        .bind(calculation => calculation.values.get((index, key)))
        .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
      let missing = cell.bind(cell => cell.formula) is Some(_) && value == Blank
      let mut text = if missing {
        "Not calculated"
      } else {
        formatted(value, style.format, self.date1904)
      }
      if printing && (missing || !style.diagnostic.is_empty()) {
        @failure.reject(
          "unsupported-print",
          if missing {
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
      let rect : @layout.Border = {
        x: dimensions.columns.position(range.left) + dx,
        y: dimensions.rows.position(range.top) + dy,
        width: dimensions.columns.position(range.right + 1) -
        dimensions.columns.position(range.left),
        height: dimensions.rows.position(range.bottom + 1) -
        dimensions.rows.position(range.top),
      }
      if !style.fill.is_empty() {
        page.fills.push({
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
          color: style.fill,
        })
      }
      if !printing {
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
        if value is Number(_) &&
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
        let horizontal = if style.horizontal != "general" {
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
            x: rect.x.max(36),
            y: rect.y.max(18),
            width: ((rect.x + rect.width).min(page.width) - rect.x.max(36)).max(
              0,
            ),
            height: ((rect.y + rect.height).min(page.height) - rect.y.max(18)).max(
              0,
            ),
          }
          for i in start..<page.texts.length() {
            page.texts[i] = (page.texts[i].0, clip)
          }
        }
      }
      let calculated = self.calculation.bind(calculation => {
        calculation.values.get((index, key))
      })
      cells.push({
        "cell": sheet.cell_json(address, self.read_only, calculated),
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
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let used = current.used()
  let extent_row = (used.bottom.max(
    if self.selection.0 == sheet {
      self.selection.1.bottom
    } else {
      1
    },
  ) +
  100).min(1048576)
  let extent_column = (used.right.max(
    if self.selection.0 == sheet {
      self.selection.1.right
    } else {
      1
    },
  ) +
  20).min(16384)
  let extent_width = dimensions.columns.position(extent_column + 1)
  let extent_height = dimensions.rows.position(extent_row + 1)
  let mut x = scroll_x.min((extent_width - width + 36).max(0))
  let mut y = scroll_y.min((extent_height - height + 18).max(0))
  if reveal && self.selection.0 == sheet {
    let focus = self.focus
    let left = dimensions.columns.position(focus.column)
    let right = left + dimensions.columns.size(focus.column)
    let top = dimensions.rows.position(focus.row)
    let bottom = top + dimensions.rows.size(focus.row)
    if left < x {
      x = left
    } else if right > x + width - 36 {
      x = (right - width + 36).max(0)
    }
    if top < y {
      y = top
    } else if bottom > y + height - 18 {
      y = (bottom - height + 18).max(0)
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
    return grid.result
  }
  let rows = dimensions.rows.visible(
    dimensions.rows.locate(y),
    dimensions.rows.locate(y + height - 18).min(extent_row),
  )
  let columns = dimensions.columns.visible(
    dimensions.columns.locate(x),
    dimensions.columns.locate(x + width - 36).min(extent_column),
  )
  let page : PagePaint = { width, height, texts: [], fills: [], strokes: [], }
  let cells = self.paint_cells(
    index,
    dimensions,
    rows,
    columns,
    page,
    36 - x,
    18 - y,
    probe,
    profile,
    false,
  )
  let style = self.styles[0]
  let header = fn(text : String, rect : @layout.Border) raise @failure.Failure {
    page.fills.push({
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      color: "f1f3f5",
    })
    page.strokes.push((rect, "d9dce1", 0.5))
    place_block(
      page,
      probe.text_block(
        text,
        @layout.TextStyle::new(style.font, 9, "333333"),
        profile,
        (rect.width - 4.5).max(1).min(14400),
        false,
      ),
      rect,
      "center",
      "center",
    )
  }
  let row_headers : Array[Json] = []
  let column_headers : Array[Json] = []
  for row in rows {
    let position = dimensions.rows.position(row) + 18 - y
    let size = dimensions.rows.size(row)
    header(row.to_string(), { x: 0, y: position, width: 36, height: size, })
    row_headers.push({ "index": row, "position": position, "size": size })
  }
  for column in columns {
    let position = dimensions.columns.position(column) + 36 - x
    let size = dimensions.columns.size(column)
    let address : Address = { row: 1, column, }
    let name = address.name()
    header(name[:name.length() - 1].to_owned(), {
      x: position,
      y: 0,
      width: size,
      height: 18,
    })
    column_headers.push({ "index": column, "position": position, "size": size })
  }
  header("", { x: 0, y: 0, width: 36, height: 18, })
  let document : @layout.PositionedDocument = {
    pages: [page.positioned()],
    fonts: probe.font_info(),
  }
  guard self.grid_id < 2147483647 else {
    @failure.reject("limit-exceeded", "Grid identity exhausted")
  }
  self.grid_id += 1
  let result : Json = {
    "id": self.grid_id,
    "revision": self.revision,
    "sheet": sheet,
    "scrollX": x,
    "scrollY": y,
    "extentWidth": extent_width,
    "extentHeight": extent_height,
    "regions": document.drawing(@layout.Images::new()),
    "outlines": probe.outline_resources(),
    "images": [],
    "cells": cells,
    "rows": row_headers,
    "columns": column_headers,
    "diagnostics": self.diagnostics,
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
    result,
  })
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
  guard x >= 36 && y >= 18 && x < grid.width && y < grid.height else {
    @failure.reject("invalid-hit", "Point is outside grid cells")
  }
  let address : Address = {
    row: grid.dimensions.rows.locate(y - 18 + grid.scroll_y),
    column: grid.dimensions.columns.locate(x - 36 + grid.scroll_x),
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
  {
    "x": grid.dimensions.columns.position(first.left) + 36 - grid.scroll_x,
    "y": grid.dimensions.rows.position(first.top) + 18 - grid.scroll_y,
    "width": grid.dimensions.columns.position(last.right + 1) -
    grid.dimensions.columns.position(first.left),
    "height": grid.dimensions.rows.position(last.bottom + 1) -
    grid.dimensions.rows.position(first.top),
  }
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
