///|
fn Grid::slicer_regions(
  self : Grid,
  object : SheetObject,
  relative : @layout.Border,
  clip? : @layout.Border,
) -> Array[Json] {
  let result : Array[Json] = []
  for (frame, visible) in self.drawing_boxes(object) {
    let rect : @layout.Border = {
      ..relative,
      x: frame.x + relative.x,
      y: frame.y + relative.y,
    }
    let visible = match clip {
      None => visible
      Some(clip) =>
        grid_intersection(visible, {
          ..clip,
          x: frame.x + clip.x,
          y: frame.y + clip.y,
        })
    }
    let visible = grid_intersection(visible, rect)
    if visible.width > 0 && visible.height > 0 {
      result.push({ "rect": rect, "clip": visible })
    }
  }
  result
}

///|
fn SheetObject::grid_object(
  self : SheetObject,
  grid : Grid,
  selected : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "kind": Json(self.kind()),
    "name": Json(self.name),
    "selected": Json(selected),
    "regions": Json(grid.drawing_regions(self)),
  }
  if self.timeline is Some(timeline) {
    let selectable = try {
      self.check_change(false, analysis_frame=true)
      true
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(..) => false
    }
    let movable = selectable &&
      (try {
        ignore(self.transform_change(self.rect, analysis_frame=true))
        true
      } catch {
        @failure.Failure(code="limit-exceeded", ..) as error => raise error
        @failure.Failure(..) => false
      })
    let geometry = timeline.geometry(self.rect.width, self.rect.height)
    fields["timeline"] = {
      "name": timeline.control.name,
      "label": timeline.control.label(),
      "frame": {
        "anchor": self.anchor,
        "x": self.rect.x,
        "y": self.rect.y,
        "width": self.rect.width,
        "height": self.rect.height,
      },
      "move": if movable {
        grid.slicer_regions(self, {
          x: 0,
          y: 0,
          width: (self.rect.width -
          (if timeline.control.time_level { 67.2 } else { 0.0 })).max(0),
          height: (if timeline.control.header {
            7.2 + timeline.header_height()
          } else {
            3.6
          }).min(self.rect.height),
        })
      } else {
        []
      },
      "periods": if selectable && !timeline.control.cache.connections.is_empty() {
        geometry.cells.filter_map(cell => {
          let (index, period, rect) = cell
          let regions = grid.slicer_regions(self, rect)
          if regions.is_empty() {
            None
          } else {
            let button : Json = {
              "index": index,
              "label": period.label,
              "selected": geometry.selection
              .map(range => range.0 < period.next && range.1 >= period.first)
              .unwrap_or(false),
              "regions": regions,
            }
            Some(button)
          }
        })
      } else {
        []
      },
      "navigation": {
        "level": timeline.control.level,
        "minimum": geometry.lower,
        "maximum": geometry.upper,
        "position": geometry.first,
        "label": timeline_period(geometry.first, timeline.control.level).label,
        "levelRegions": if selectable && timeline.control.time_level {
          grid.slicer_regions(self, {
            x: (self.rect.width - 67.2).max(7.2),
            y: 7.2,
            width: geometry.width.min(60),
            height: geometry.header,
          })
        } else {
          []
        },
        "scrollRegions": if selectable && timeline.control.scrollbar {
          grid.slicer_regions(self, {
            x: 7.2,
            y: (self.rect.height - 18).max(0),
            width: geometry.width,
            height: self.rect.height.min(18),
          })
        } else {
          []
        },
      },
      "handles": if selectable {
        geometry.handles.filter_map(item => {
          let (handle, index, value, rect) = item
          let regions = grid.slicer_regions(self, rect)
          if regions.is_empty() {
            None
          } else {
            let result : Json = {
              "handle": handle,
              "index": index,
              "value": value,
              "regions": regions,
            }
            Some(result)
          }
        })
      } else {
        []
      },
    }
  }
  if self.slicer is Some(slicer) {
    let geometry = slicer.geometry(
      self.rect.width,
      self.rect.height,
      probe,
      profile,
    )
    let movable = try {
      self.check_change(false, analysis_frame=true)
      ignore(self.transform_change(self.rect))
      true
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(..) => false
    }
    fields["slicer"] = {
      "name": slicer.control.name,
      "caption": slicer.control.caption,
      "frame": {
        "anchor": self.anchor,
        "x": self.rect.x,
        "y": self.rect.y,
        "width": self.rect.width,
        "height": self.rect.height,
      },
      "move": if movable {
        grid.slicer_regions(self, {
          x: 0,
          y: 0,
          width: geometry.multi
          .map(rect => rect.x)
          .unwrap_or(self.rect.width)
          .max(0),
          height: (if geometry.header > 0 { geometry.header } else { 3.6 }).min(
            self.rect.height,
          ),
        })
      } else {
        []
      },
      "start": (slicer.control.start / slicer.control.columns).min(
        geometry.maximum / slicer.control.columns,
      ),
      "maximum": geometry.maximum / slicer.control.columns,
      "page": geometry.page,
      "buttons": geometry.buttons.map(pair => {
        let (position, rect) = pair
        let item = slicer.control.cache.members[position]
        let button : Json = {
          "index": item.index,
          "label": if item.value == Blank {
            "(blank)"
          } else {
            item.value.display()
          },
          "selected": item.selected,
          "hasData": item.hasData,
          "regions": grid.slicer_regions(self, rect, clip=geometry.body),
        }
        button
      }),
      "clear": geometry.clear
      .map(rect => grid.slicer_regions(self, rect))
      .unwrap_or([]),
      "multi": geometry.multi
      .map(rect => grid.slicer_regions(self, rect))
      .unwrap_or([]),
      "previous": geometry.previous
      .map(rect => grid.slicer_regions(self, rect))
      .unwrap_or([]),
      "next": geometry.next
      .map(rect => grid.slicer_regions(self, rect))
      .unwrap_or([]),
      "scroll": geometry.scroll
      .map(track => {
        let arrow = 11.25.min(track.height / 2)
        grid.slicer_regions(self, {
          ..track,
          y: track.y + arrow,
          height: (track.height - 2 * arrow).max(0),
        })
      })
      .unwrap_or([]),
    }
  }
  Json(fields)
}

///|
fn Session::slicer_target(
  self : Session,
  revision : Int,
  sheet : String,
  layout : Int,
  id : String,
) -> (Grid, SheetObject, SlicerDrawing, SlicerGeometry) raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.drawing_grid(layout)
  guard grid.sheet == sheet &&
    id.length() <= 10 &&
    grid.objects.iter().find_first(object => object.id == id) is Some(object) &&
    object.slicer is Some(slicer) &&
    !grid.drawing_regions(object).is_empty() else {
    @failure.reject(
      "invalid-operation", "Slicer is outside the visible worksheet",
    )
  }
  guard self.font_context is Some((probe, profile)) else {
    @failure.reject("missing-font", "Measure slicer buttons before interaction")
  }
  (
    grid,
    object,
    slicer,
    slicer.geometry(object.rect.width, object.rect.height, probe, profile),
  )
}

///|
/// Selects a visible native member, or clears the filter when index is absent.
pub fn Session::select_slicer(
  self : Session,
  revision : Int,
  sheet : String,
  layout : Int,
  id : String,
  index : Int?,
  additive : Bool,
) -> Json raise @failure.Failure {
  let (grid, object, slicer, geometry) = self.slicer_target(
    revision, sheet, layout, id,
  )
  let indices = match index {
    None => {
      guard !additive &&
        geometry.clear is Some(rect) &&
        !grid.slicer_regions(object, rect).is_empty() else {
        @failure.reject(
          "invalid-operation", "Slicer clear button is not visible",
        )
      }
      slicer.control.cache.members.map(item => item.index)
    }
    Some(index) => {
      guard geometry.buttons
        .iter()
        .find_first(pair => slicer.control.cache.members[pair.0].index == index)
        is Some((_, rect)) &&
        !grid.slicer_regions(object, rect, clip=geometry.body).is_empty() else {
        @failure.reject("invalid-operation", "Slicer member is not visible")
      }
      if additive {
        slicer.control.cache.members
        .filter(item => {
          if item.index == index {
            !item.selected
          } else {
            item.selected
          }
        })
        .map(item => item.index)
      } else {
        [index]
      }
    }
  }
  // The member-filter contract requires at least one selected item.
  if indices.is_empty() {
    return self.query()
  }
  self.filter_slicer(revision, sheet, slicer.control.name, indices)
}

///|
/// Sets the absolute native slicer row in session view state without adding document history.
pub fn Session::scroll_slicer(
  self : Session,
  revision : Int,
  sheet : String,
  layout : Int,
  id : String,
  position : Int,
) -> Json raise @failure.Failure {
  let (_, _, slicer, geometry) = self.slicer_target(revision, sheet, layout, id)
  guard position >= 0 && position <= 4095 && geometry.scroll is Some(_) else {
    @failure.reject("invalid-operation", "Slicer has no scrollable view")
  }
  let start = position.min(geometry.maximum / slicer.control.columns) *
    slicer.control.columns
  if start != slicer.control.start {
    let key = (sheet, slicer.control.name)
    guard self.slicer_scrolls.contains(key) ||
      self.slicer_scrolls.length() < 4096 else {
      @failure.reject("limit-exceeded", "Slicer view state exceeds budget")
    }
    self.slicer_scrolls[key] = start
    self.grid = None
  }
  self.query()
}
