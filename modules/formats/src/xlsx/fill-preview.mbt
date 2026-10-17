///|
pub(all) enum FillTarget {
  FillPoint(Double, Double)
  FillDirection(String)
}

///|
pub fn Session::fill_preview(
  self : Session,
  id : Int,
  target : FillTarget,
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
  let source = self.selection.1
  let address : Address = match target {
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
  let direction = if dx == 0 && dy == 0 {
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
  let range = if vertical {
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
  guard (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Fill preview exceeds 4096 cells")
  }
  let frozen = self.sheets[self.sheet_index(grid.sheet)].frozen
  let end = {
    top: range.bottom,
    bottom: range.bottom,
    left: range.right,
    right: range.right,
  }
  {
    "source": source.name(),
    "range": range.name(),
    "direction": direction,
    "geometry": grid.range_geometry(range, frozen),
    "end": grid.range_geometry(end, frozen),
  }
}
