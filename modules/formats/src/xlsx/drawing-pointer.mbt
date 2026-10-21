///|
fn Grid::drawing_regions(self : Grid, object : SheetObject) -> Array[Json] {
  let regions : Array[Json] = []
  if !object.visible {
    return regions
  }
  for row in self.rows {
    for column in self.columns {
      let rect = grid_rect(
        {
          ..object.rect,
          x: object.rect.x + self.header_width - column.scroll,
          y: object.rect.y + self.header_height - row.scroll,
        },
        self.width,
        self.rtl,
      )
      let clip = grid_rect(
        {
          x: self.header_width + column.start,
          y: self.header_height + row.start,
          width: column.size,
          height: row.size,
        },
        self.width,
        self.rtl,
      )
      let rect = object.paint_bounds(rect)
      let rect : @layout.Border = if object.kind() == "line" {
        {
          x: rect.x - (6.0 - rect.width).max(0) / 2,
          y: rect.y - (6.0 - rect.height).max(0) / 2,
          width: rect.width.max(6),
          height: rect.height.max(6),
        }
      } else {
        rect
      }
      let visible = grid_intersection(rect, clip)
      if visible.width > 0 && visible.height > 0 {
        regions.push({ "rect": rect, "clip": visible })
      }
    }
  }
  regions
}

///|
fn Session::drawing_grid(
  self : Session,
  id : Int,
) -> Grid raise @failure.Failure {
  self.check()
  guard self.grid is Some(grid) &&
    grid.id == id &&
    grid.revision == self.revision &&
    grid.sheet == self.selection.0 else {
    @failure.reject("stale-layout", "Worksheet object geometry changed")
  }
  grid
}

///|
fn Session::drawing_pointer_state(
  self : Session,
  grid : Grid,
  object : SheetObject?,
) -> Json {
  {
    "revision": self.revision,
    "sheet": grid.sheet,
    "id": object.map(p => Json(p.id)).unwrap_or(Json::null()),
    "regions": object.map(p => grid.drawing_regions(p)).unwrap_or([]),
  }
}

///|
pub fn Session::select_drawing(
  self : Session,
  revision : Int,
  layout : Int,
  id : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.drawing_grid(layout)
  let object = id.map(id => {
    let object = grid.objects
      .iter()
      .find_first(p => p.id == id)
      .unwrap_or_else(() => {
        @failure.reject(
          "invalid-operation", "Worksheet object no longer exists",
        )
      })
    guard !grid.drawing_regions(object).is_empty() else {
      @failure.reject("invalid-operation", "Worksheet object is not visible")
    }
    object.check_change(false)
    object
  })
  self.drawing_selection = object.map(p => (grid.sheet, p.id))
  self.drawing_pointer_state(grid, object)
}

///|
fn SheetObject::pointer_rect(
  self : SheetObject,
  grid : Grid,
  handle : Int,
  dx : Double,
  dy : Double,
) -> @layout.Border raise @failure.Failure {
  guard handle >= 0 &&
    handle <= 4 &&
    [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet object pointer delta",
    )
  }
  let dx = if grid.rtl { -dx } else { dx }
  let rect = self.rect
  let rect = if handle == 0 {
    { ..rect, x: (rect.x + dx).max(0), y: (rect.y + dy).max(0), }
  } else {
    guard self.shape is Some(_) || (rect.width > 0 && rect.height > 0) else {
      @failure.reject(
        "invalid-operation", "Expand collapsed object anchors before resizing",
      )
    }
    let left = if grid.rtl {
      handle == 2 || handle == 3
    } else {
      handle == 1 || handle == 4
    }
    let top = handle == 1 || handle == 2
    let aspect = self.media is Some(_) ||
      self.tree.document
      .nodes()
      .any(node => {
        node.start >= self.source.start &&
        node.end <= self.source.end &&
        node.name == "spLocks" &&
        flag(node, "noChangeAspect")
      })
    if !aspect {
      let minimum = if self.kind() == "line" { 0.0 } else { 0.1 }
      let width = (rect.width + (if left { -dx } else { dx }))
        .max(minimum)
        .min(14400)
      let height = (rect.height + (if top { -dy } else { dy }))
        .max(minimum)
        .min(14400)
      let result : @layout.Border = {
        x: if left {
          rect.x + rect.width - width
        } else {
          rect.x
        },
        y: if top {
          rect.y + rect.height - height
        } else {
          rect.y
        },
        width,
        height,
      }
      ignore(self.shape_settings(result).checked(grid.dimensions))
      self.check_change(false, rect=result)
      return result
    }
    guard rect.width > 0 && rect.height > 0 else {
      @failure.reject(
        "protected-content", "Collapsed shape aspect ratio is locked",
      )
    }
    let sx = 1.0 + (if left { -dx } else { dx }) / rect.width
    let sy = 1.0 + (if top { -dy } else { dy }) / rect.height
    let factor = (if (sx - 1).abs() > (sy - 1).abs() { sx } else { sy })
      .max((0.1 / rect.width).max(0.1 / rect.height))
      .min((14400.0 / rect.width).min(14400.0 / rect.height))
    let width = rect.width * factor
    let height = rect.height * factor
    {
      x: if left {
        rect.x + rect.width - width
      } else {
        rect.x
      },
      y: if top {
        rect.y + rect.height - height
      } else {
        rect.y
      },
      width,
      height,
    }
  }
  if self.shape is Some(_) {
    ignore(self.shape_settings(rect).checked(grid.dimensions))
  } else {
    check_picture_rect(self.anchor, rect, grid.dimensions)
  }
  self.check_change(false, rect~)
  rect
}

///|
pub fn Session::drawing_gesture(
  self : Session,
  revision : Int,
  layout : Int,
  handle : Int,
  dx : Double,
  dy : Double,
  commit : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.drawing_grid(layout)
  guard self.drawing_selection is Some((sheet, id)) && sheet == grid.sheet else {
    @failure.reject("invalid-operation", "Select a worksheet object first")
  }
  let object = grid.objects
    .iter()
    .find_first(p => p.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet object no longer exists")
    })
  let rect = object.pointer_rect(grid, handle, dx, dy)
  let view = if commit {
    self
  } else {
    { ..self, history: [], redo: [], history_bytes: 0, }
  }
  let query = if object.shape is Some(_) {
    view.set_shape(
      self.revision,
      sheet,
      id,
      object.shape_settings(rect),
      probe,
      profile,
    )
  } else {
    view.set_picture(
      self.revision,
      sheet,
      id,
      object.anchor,
      rect,
      object.name,
      object.description,
      probe,
      profile,
      crop=object.crop,
    )
  }
  let selection = self.drawing_pointer_state(grid, Some({ ..object, rect, }))
  let drawing = if commit {
    Json::null()
  } else {
    view.viewport(
      sheet,
      grid.scroll_x,
      grid.scroll_y,
      grid.width,
      grid.height,
      probe,
      profile,
      images~,
    )
  }
  if !commit {
    self.grid_id = view.grid_id
  }
  {
    "query": if commit {
      query
    } else {
      Json::null()
    },
    "drawing": drawing,
    "selection": selection,
  }
}
