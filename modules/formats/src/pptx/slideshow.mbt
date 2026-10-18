///|
fn Session::show_neighbor(self : Session, index : Int, forward : Bool) -> Int? {
  for step in 1..<=self.slides.length() {
    let next = index + (if forward { step } else { -step })
    if next >= 0 && next < self.slides.length() && !self.slides[next].hidden {
      return Some(next)
    }
  }
  None
}

///|
pub fn Session::control_show(
  self : Session,
  revision : Int,
  action : String,
  slide : String,
  time : Double,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  show_time(time)
  guard [
      "start", "end", "next", "previous", "first", "last", "goto", "pause", "resume",
      "tick", "click",
    ].contains(action) &&
    (action == "start" || action == "goto" || slide.is_empty()) else {
    @failure.reject("invalid-operation", "Invalid slideshow action or target")
  }
  let old = self.showing.map(show => show.advance(time))
  let show = if action == "end" {
    None
  } else if action == "start" {
    self.check_idle()
    let index = if slide.is_empty() {
      self
      .show_neighbor(-1, true)
      .unwrap_or_else(() => {
        @failure.reject("invalid-slide", "There are no visible slides")
      })
    } else {
      self.index(slide)
    }
    Some(self.show_scene(index, None, time, true))
  } else {
    guard old is Some(current) else {
      @failure.reject("show-required", "Start the slideshow first")
    }
    if action == "tick" {
      self.show_tick(current)
    } else if action == "pause" || action == "resume" {
      Some({ ..current, paused: action == "pause", })
    } else if (action == "next" || action == "click") &&
      current.effect is Some(_) {
      // A click completes an in-flight transition before advancing another page.
      Some(current.finish_entry())
    } else if (action == "next" || action == "click") &&
      current.animations_running() {
      Some(current.finish_animations())
    } else if (action == "next" || action == "click") &&
      current.step < current.animations.length() {
      Some(current.schedule_animations(current.elapsed))
    } else if action == "click" && !current.advance.click {
      Some(current)
    } else {
      let next = match action {
        "next" | "click" => self.show_neighbor(current.index, true)
        "previous" =>
          Some(
            self.show_neighbor(current.index, false).unwrap_or(current.index),
          )
        "first" => Some(self.show_neighbor(-1, true).unwrap_or(current.index))
        "last" =>
          Some(
            self
            .show_neighbor(self.slides.length(), false)
            .unwrap_or(current.index),
          )
        "goto" => Some(self.index(slide))
        _ => abort("Validated slideshow action")
      }
      next.map(index => {
        if index == current.index {
          current
        } else {
          self.show_scene(
            index,
            Some(current.index),
            time,
            action != "previous",
            leaving=current.animation_opacity(),
          )
        }
      })
    }
  }
  let result = self.show_state(show)
  self.showing = show
  if show is None {
    self.show_drawing = None
  }
  result
}

///|
pub fn Session::show_layout(
  self : Session,
  revision : Int,
  time : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.showing is Some(show) else {
    @failure.reject("show-required", "Start the slideshow first")
  }
  let show = show.advance(time)
  let key = Json::array([
    Json(self.revision),
    Json(show.index),
    Json(show.from),
    Json(profile),
    Json(probe.font_info()),
  ]).stringify()
  let drawing = if self.show_drawing is Some(drawing) && drawing.key == key {
    drawing
  } else {
    let pages : Array[@layout.PositionedPage] = []
    let parts : Array[Array[(String, Array[@layout.DrawCommand])]] = []
    let keys : Array[String] = []
    for
      role, i in [
        Some(show.index),
        self.show_neighbor(show.index, true),
        show.from,
      ] {
      if i is Some(i) {
        let slide = self.slides[i]
        let fragments : Array[(String, Array[@layout.PositionedPrimitive])] = []
        let (page, _, diagnostics) = paint_slide(
          slide,
          self.width,
          self.height,
          probe,
          profile,
          self.tile_sizes(slide),
          parts=if role == 2 || (role == 0 && !show.animations.is_empty()) {
            Some(fragments)
          } else {
            None
          },
        )
        guard diagnostics.is_empty() else {
          @failure.reject(
            "unsupported-show",
            diagnostics.join("; "),
            part=slide.tree.part,
          )
        }
        pages.push(page)
        parts.push(
          fragments.map(fragment => {
            let (id, primitives) = fragment
            let document : @layout.PositionedDocument = {
              pages: [{ ..page, primitives, }],
              fonts: probe.font_info(),
            }
            (id, document.drawing(images, clear=id.is_empty())[0].commands)
          }),
        )
        for key in slide.image_keys() {
          if !keys.contains(key) {
            keys.push(key)
          }
        }
      }
    }
    let document : @layout.PositionedDocument = {
      pages,
      fonts: probe.font_info(),
    }
    let resources : Array[String] = []
    for key in keys {
      let identity = images.get(key).identity
      if !resources.contains(identity) {
        resources.push(identity)
      }
    }
    let drawing : ShowDrawing = {
      key,
      regions: document.drawing(images),
      parts,
      images: resources,
    }
    self.show_drawing = Some(drawing)
    drawing
  }
  let painted = drawing.regions.copy()
  painted[0] = animated_region(
    painted[0],
    drawing.parts[0],
    show.animation_opacity(),
  )
  if show.from is Some(_) {
    let last = painted.length() - 1
    painted[last] = animated_region(
      painted[last],
      drawing.parts[last],
      show.leaving,
    )
  }
  let regions = [self.show_region(show, painted)]
  if self.show_neighbor(show.index, true) is Some(_) {
    regions.push(drawing.regions[1])
  }
  guard self.sequence < 2147483647 else {
    @failure.reject("limit-exceeded", "Layout identity exhausted")
  }
  self.sequence += 1
  self.showing = Some(show)
  {
    "id": self.sequence,
    "revision": revision,
    "regions": regions,
    "outlines": probe.outline_resources(),
    "images": drawing.images,
    "animating": !show.paused &&
    (
      show.effect is Some(_) ||
      show.advance.after is Some(_) ||
      show.animations_running()
    ),
  }
}

///|
pub fn Session::show_image_keys(
  self : Session,
) -> Array[String] raise @failure.Failure {
  self.check()
  let keys : Array[String] = []
  if self.showing is Some(show) {
    for i in [Some(show.index), self.show_neighbor(show.index, true), show.from] {
      if i is Some(i) {
        for key in self.slides[i].image_keys() {
          if !keys.contains(key) {
            keys.push(key)
          }
        }
      }
    }
  }
  guard keys.length() <= 256 else {
    @failure.reject("limit-exceeded", "Slideshow images exceed 256")
  }
  keys
}
