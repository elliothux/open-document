///|
pub(all) enum FillTarget {
  FillPoint(Double, Double)
  FillDirection(String)
  FillAdjacent
}

///|
pub fn Session::fill_preview(
  self : Session,
  id : Int,
  target : FillTarget,
  ctrl~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check()
  guard self.grid is Some(grid) &&
    grid.id == id &&
    grid.revision == self.revision &&
    grid.sheet == self.selection.0 else {
    @failure.reject(
      "stale-layout", "Fill preview requires current grid geometry",
    )
  }
  let original = self.selection.1
  let source = self.sheets[self.sheet_index(grid.sheet)].merge_target(original)
  let address : Address = match target {
    FillAdjacent => {
      let range = self.adjacent_fill(self.sheet_index(grid.sheet), source)
      { row: range.bottom, column: range.right, }
    }
    FillPoint(x, y) => Address::parse(self.hit(id, x, y))
    FillDirection(direction) =>
      match direction {
        "down" =>
          { row: (source.bottom + 1).min(1048576), column: source.right, }
        "up" => { row: (source.top - 1).max(1), column: source.left, }
        "right" =>
          { row: source.bottom, column: (source.right + 1).min(16384), }
        "left" => { row: source.top, column: (source.left - 1).max(1), }
        _ =>
          @failure.reject("invalid-operation", "Invalid fill preview direction")
      }
  }
  let rows = grid.dimensions.rows
  let columns = grid.dimensions.columns
  let dy = if address.row > source.bottom {
    rows.position(address.row + 1) - rows.position(source.bottom + 1)
  } else if address.row < source.top {
    rows.position(source.top) - rows.position(address.row)
  } else {
    0
  }
  let dx = if address.column > source.right {
    columns.position(address.column + 1) - columns.position(source.right + 1)
  } else if address.column < source.left {
    columns.position(source.left) - columns.position(address.column)
  } else {
    0
  }
  let vertical = dy > 0 && dy >= dx
  let mut direction = if dx == 0 && dy == 0 {
    match target {
      FillDirection(direction) => direction
      _ => "down"
    }
  } else if vertical {
    if address.row < source.top {
      "up"
    } else {
      "down"
    }
  } else if address.column < source.left {
    "left"
  } else {
    "right"
  }
  let mut range = if vertical {
    {
      ..source,
      top: source.top.min(address.row),
      bottom: source.bottom.max(address.row),
    }
  } else {
    {
      ..source,
      left: source.left.min(address.column),
      right: source.right.max(address.column),
    }
  }
  let frozen = self.sheets[self.sheet_index(grid.sheet)].frozen
  let mut mode = "auto"
  if target is FillPoint(x, y) && source.contains(address) {
    let cell = grid.range_rect(
      {
        top: address.row,
        bottom: address.row,
        left: address.column,
        right: address.column,
      },
      frozen,
    )
    let rect = grid.range_rect(source, frozen)
    let vertical = if address.column == source.right &&
      address.row != source.bottom {
      true
    } else if address.row == source.bottom && address.column != source.right {
      false
    } else {
      (rect.y + rect.height - y).abs() >
      (x - (if grid.rtl { rect.x } else { rect.x + rect.width })).abs()
    }
    let edge = if vertical {
      address.row + (if y >= cell.y + cell.height / 2 { 1 } else { 0 })
    } else {
      address.column +
      (if (if grid.rtl {
          x <= cell.x + cell.width / 2
        } else {
          x >= cell.x + cell.width / 2
        }) {
        1
      } else {
        0
      })
    }
    if edge <= (if vertical { source.bottom } else { source.right }) {
      mode = "shrink"
      direction = if vertical { "up" } else { "left" }
      range = if vertical {
        { ..source, top: edge, }
      } else {
        { ..source, left: edge, }
      }
    }
  }
  guard (source.bottom - source.top + 1).to_int64() *
    (source.right - source.left + 1).to_int64() <=
    4096 &&
    (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Fill preview exceeds 4096 cells")
  }
  let selected = if mode == "shrink" {
    fill_remainder(source, range, direction)
  } else {
    range
  }
  if ctrl && mode == "auto" && source != range {
    let current = self.sheets[self.sheet_index(grid.sheet)]
    let address : Address = { row: source.top, column: source.left, }
    mode = if source.top == source.bottom &&
      source.left == source.right &&
      current.cells.get(address.name()) is Some(cell) &&
      cell.formula is None &&
      cell.value is Number(_) &&
      series_calendar_kind(self.styles[current.style_at(address)].format).is_empty() {
      "linear"
    } else {
      "copy"
    }
  }
  let end = {
    top: selected.bottom,
    bottom: selected.bottom,
    left: selected.right,
    right: selected.right,
  }
  {
    "source": original.name(),
    "range": range.name(),
    "direction": direction,
    "mode": mode,
    "geometry": grid.range_geometry(range, frozen),
    "end": grid.range_geometry(end, frozen),
  }
}
