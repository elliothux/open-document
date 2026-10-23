///|
pub(all) struct DrawingViewport {
  origin_x : Double
  origin_y : Double
  scroll_x : Double
  scroll_y : Double
}

///|
fn Grid::drawing_delta(
  self : Grid,
  viewport : DrawingViewport,
  dx : Double,
  dy : Double,
) -> (Double, Double) raise @failure.Failure {
  guard [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) &&
    viewport.origin_x >= 0 &&
    viewport.origin_x <= self.width &&
    viewport.origin_y >= 0 &&
    viewport.origin_y <= self.height &&
    viewport.scroll_x >= 0 &&
    viewport.scroll_x <= 1000000000 &&
    viewport.scroll_y >= 0 &&
    viewport.scroll_y <= 1000000000 else {
    @failure.reject(
      "invalid-viewport", "Invalid worksheet object pointer viewport",
    )
  }
  let boundary_x = self.header_width +
    self.columns.iter().find_first(b => b.frozen).map(b => b.size).unwrap_or(0)
  let boundary_y = self.header_height +
    self.rows.iter().find_first(b => b.frozen).map(b => b.size).unwrap_or(0)
  let x = if self.rtl {
    self.width - viewport.origin_x
  } else {
    viewport.origin_x
  }
  let logical_dx = if self.rtl { -dx } else { dx }
  let logical_dx = logical_dx +
    (if x + logical_dx >= boundary_x { viewport.scroll_x } else { 0 }) -
    (if x >= boundary_x { self.scroll_x } else { 0 })
  let dy = dy +
    (if viewport.origin_y + dy >= boundary_y { viewport.scroll_y } else { 0 }) -
    (if viewport.origin_y >= boundary_y { self.scroll_y } else { 0 })
  (if self.rtl { -logical_dx } else { logical_dx }, dy)
}

///|
fn Grid::drawing_boxes(
  self : Grid,
  object : SheetObject,
) -> Array[(@layout.Border, @layout.Border)] {
  let regions : Array[(@layout.Border, @layout.Border)] = []
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
        regions.push((rect, visible))
      }
    }
  }
  regions
}

///|
fn Grid::drawing_regions(self : Grid, object : SheetObject) -> Array[Json] {
  self.drawing_boxes(object).map(pair => { "rect": pair.0, "clip": pair.1 })
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
    object.check_change(false, slicer_frame=object.slicer is Some(_))
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
        node.name.has_suffix("Locks") &&
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
      if self.chart is Some(_) || self.slicer is Some(_) {
        check_picture_rect(self.anchor, result, grid.dimensions)
      } else {
        ignore(self.shape_settings(result).checked(grid.dimensions))
      }
      self.check_change(false, rect=result, slicer_frame=self.slicer is Some(_))
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
  self.check_change(false, rect~, slicer_frame=self.slicer is Some(_))
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
  viewport~ : DrawingViewport? = None,
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
  let (dx, dy) = match viewport {
    Some(viewport) => grid.drawing_delta(viewport, dx, dy)
    None => (dx, dy)
  }
  let rect = object.pointer_rect(grid, handle, dx, dy)
  let scroll_x = viewport.map(v => v.scroll_x).unwrap_or(grid.scroll_x)
  let scroll_y = viewport.map(v => v.scroll_y).unwrap_or(grid.scroll_y)
  let view = if commit {
    self
  } else {
    { ..self, history: [], redo: [], history_bytes: 0, }
  }
  let query = if object.slicer is Some(_) {
    view.set_slicer_frame(
      self.revision,
      sheet,
      id,
      object.anchor,
      rect,
      probe,
      profile,
    )
  } else if object.chart is Some(_) {
    view.set_chart_frame(
      self.revision,
      sheet,
      id,
      object.anchor,
      rect,
      object.name,
      object.description,
      probe,
      profile,
    )
  } else if object.shape is Some(_) {
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
  let drawing = if commit {
    Json::null()
  } else {
    view.viewport(
      sheet,
      scroll_x,
      scroll_y,
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
  let selection_grid = if commit {
    {
      ..grid,
      rows: grid.rows.map(b => {
        ..b,
        scroll: if b.frozen {
          0
        } else {
          scroll_y
        },
      }),
      columns: grid.columns.map(b => {
        ..b,
        scroll: if b.frozen {
          0
        } else {
          scroll_x
        },
      }),
    }
  } else {
    view.grid.unwrap()
  }
  let selection = self.drawing_pointer_state(
    selection_grid,
    Some({ ..object, rect, }),
  )
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
