///|
fn Grid::picture_regions(self : Grid, picture : Picture) -> Array[Json] {
  let regions : Array[Json] = []
  if !picture.visible {
    return regions
  }
  for row in self.rows {
    for column in self.columns {
      let rect = grid_rect(
        {
          ..picture.rect,
          x: picture.rect.x + self.header_width - column.scroll,
          y: picture.rect.y + self.header_height - row.scroll,
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
      let visible = grid_intersection(rect, clip)
      if visible.width > 0 && visible.height > 0 {
        regions.push({ "rect": rect, "clip": visible })
      }
    }
  }
  regions
}

///|
fn Session::picture_grid(
  self : Session,
  id : Int,
) -> Grid raise @failure.Failure {
  self.check()
  guard self.grid is Some(grid) &&
    grid.id == id &&
    grid.revision == self.revision &&
    grid.sheet == self.selection.0 else {
    @failure.reject("stale-layout", "Worksheet picture geometry changed")
  }
  grid
}

///|
fn Session::picture_pointer_state(
  self : Session,
  grid : Grid,
  picture : Picture?,
) -> Json {
  {
    "revision": self.revision,
    "sheet": grid.sheet,
    "id": picture.map(p => Json(p.id)).unwrap_or(Json::null()),
    "regions": picture.map(p => grid.picture_regions(p)).unwrap_or([]),
  }
}

///|
pub fn Session::select_picture(
  self : Session,
  revision : Int,
  layout : Int,
  id : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.picture_grid(layout)
  let picture = id.map(id => {
    let picture = grid.pictures
      .iter()
      .find_first(p => p.id == id)
      .unwrap_or_else(() => {
        @failure.reject(
          "invalid-operation", "Worksheet picture no longer exists",
        )
      })
    guard !grid.picture_regions(picture).is_empty() else {
      @failure.reject("invalid-operation", "Worksheet picture is not visible")
    }
    picture.check_change(false)
    picture
  })
  self.picture_selection = picture.map(p => (grid.sheet, p.id))
  self.picture_pointer_state(grid, picture)
}

///|
fn Picture::pointer_rect(
  self : Picture,
  grid : Grid,
  handle : Int,
  dx : Double,
  dy : Double,
) -> @layout.Border raise @failure.Failure {
  guard handle >= 0 &&
    handle <= 4 &&
    [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet picture pointer delta",
    )
  }
  let dx = if grid.rtl { -dx } else { dx }
  let rect = self.rect
  let rect = if handle == 0 {
    { ..rect, x: (rect.x + dx).max(0), y: (rect.y + dy).max(0), }
  } else {
    guard rect.width > 0 && rect.height > 0 else {
      @failure.reject(
        "invalid-operation", "Expand collapsed picture anchors before resizing",
      )
    }
    let left = if grid.rtl {
      handle == 2 || handle == 3
    } else {
      handle == 1 || handle == 4
    }
    let top = handle == 1 || handle == 2
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
  check_picture_rect(self.anchor, rect, grid.dimensions)
  self.check_change(false, rect~)
  rect
}

///|
pub fn Session::picture_gesture(
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
  let grid = self.picture_grid(layout)
  guard self.picture_selection is Some((sheet, id)) && sheet == grid.sheet else {
    @failure.reject("invalid-operation", "Select a worksheet picture first")
  }
  let picture = grid.pictures
    .iter()
    .find_first(p => p.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet picture no longer exists")
    })
  let rect = picture.pointer_rect(grid, handle, dx, dy)
  let view = if commit {
    self
  } else {
    { ..self, history: [], redo: [], history_bytes: 0, }
  }
  let query = view.set_picture(
    self.revision,
    sheet,
    id,
    picture.anchor,
    rect,
    picture.name,
    picture.description,
    probe,
    profile,
  )
  let selection = self.picture_pointer_state(grid, Some({ ..picture, rect, }))
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
