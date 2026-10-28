///|
fn Session::show_neighbor(
  self : Session,
  show : ShowState,
  forward : Bool,
  position~ : Int32 = show.position,
) -> Int32? {
  for step in 1..<=show.route.length() {
    let next = position + (if forward { step } else { -step })
    if next >= 0 &&
      next < show.route.length() &&
      !self.slides[show.route[next]].hidden {
      return Some(next)
    }
  }
  if forward && show.cycling {
    show.route.search_by(index => !self.slides[index].hidden)
  } else {
    None
  }
}

///|
pub fn Session::control_show(
  self : Session,
  revision : Int32,
  action : String,
  slide : String,
  time : Double,
  custom~ : String? = None,
  layout~ : Int32? = None,
  point~ : (Double, Double)? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  show_time(time)
  guard [
      "start", "startSettings", "end", "next", "previous", "first", "last", "goto",
      "pause", "resume", "tick", "click", "gotoPosition", "followLink", "saveInk",
    ].contains(action) &&
    (
      ["start", "goto", "gotoPosition", "followLink"].contains(action) ||
      slide.is_empty()
    ) &&
    (custom is None || (action == "start" && slide.is_empty())) &&
    (point is None || (action == "click" && layout is Some(_))) &&
    (layout is None || action == "followLink" || point is Some(_)) &&
    (action != "followLink" || layout is Some(_)) else {
    @failure.reject("invalid-operation", "Invalid slideshow action or target")
  }
  if action == "saveInk" {
    if self.showing is Some(show) {
      ignore(show.advance(time))
    }
    return self.save_show_ink()
  }
  if layout is Some(layout) {
    let drawing = self.current_show_frame(layout)
    let link = if action == "followLink" {
      let index = number(slide, 0, 4095).to_int()
      guard index.to_string() == slide else {
        @failure.reject("invalid-operation", "Invalid slideshow link identity")
      }
      Some(index)
    } else {
      let (x, y) = point.unwrap()
      self.show_link_hit(drawing, x, y)
    }
    if link is Some(index) {
      return self.apply_show_link(drawing, index, time)
    }
  }
  let old = self.showing.map(show => show.advance(time))
  let (old, media_sequence) = if ["start", "startSettings", "end"].contains(
      action,
    ) {
    (old, self.media_sequence)
  } else {
    self.show_media_cues(old)
  }
  let show = if action == "end" {
    None
  } else if action == "start" || action == "startSettings" {
    self.check_idle()
    let settings = self.read_show_settings()
    let custom = if action == "startSettings" {
      match settings.slides {
        ShowCustom(id) => Some(id)
        _ => None
      }
    } else {
      custom
    }
    let route = if custom is Some(id) {
      let shows = self.read_custom_shows()
      guard shows.iter().find_first(show => show.id == id) is Some(show) else {
        @failure.reject("invalid-operation", "Custom show no longer exists")
      }
      show.slides.map(slide => self.index(slide))
    } else if action == "startSettings" &&
      settings.slides is ShowRange(first, last) {
      Array::makei(last - first + 1, i => first - 1 + i)
    } else {
      Array::makei(self.slides.length(), i => i)
    }
    let position = if slide.is_empty() {
      route
      .search_by(index => !self.slides[index].hidden)
      .unwrap_or_else(() => {
        @failure.reject(
          "invalid-slide", "There are no visible slides in this show",
        )
      })
    } else {
      self.index(slide)
    }
    Some(self.show_scene(route, position, custom, None, time, true))
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
        "next" | "click" => self.show_neighbor(current, true)
        "previous" =>
          Some(self.show_neighbor(current, false).unwrap_or(current.position))
        "first" =>
          Some(
            self
            .show_neighbor(current, true, position=-1)
            .unwrap_or(current.position),
          )
        "last" =>
          Some(
            self
            .show_neighbor(current, false, position=current.route.length())
            .unwrap_or(current.position),
          )
        "goto" => {
          let index = self.index(slide)
          Some(
            current.route
            .search_by(item => item == index)
            .unwrap_or_else(() => {
              @failure.reject(
                "invalid-slide", "Slide is outside the current show",
              )
            }),
          )
        }
        "gotoPosition" =>
          Some(
            number(slide, 0, (current.route.length() - 1).to_double()).to_int(),
          )
        _ => abort("Validated slideshow action")
      }
      next.map(position => {
        if position == current.position &&
          !(current.cycling && ["next", "click"].contains(action)) {
          current
        } else {
          self.show_scene(
            current.route,
            position,
            current.custom,
            Some(current.index),
            time,
            action != "previous",
            leaving=current.animation_state(),
            last_view=Some((current.route, current.position, current.custom)),
          )
        }
      })
    }
  }
  let (show, media_sequence) = self.show_media_cues(
    show,
    initial=media_sequence,
  )
  let result = self.show_state(show)
  self.showing = show
  self.media_sequence = media_sequence
  if action != "tick" {
    self.invalidate_show_frame()
  }
  if show is None {
    self.show_drawing = None
  }
  result
}

///|
pub fn Session::show_layout(
  self : Session,
  revision : Int32,
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
    Json(show.route),
    Json(show.position),
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
    let texts : Array[TextGeometry] = []
    for
      role, i in [
        Some(show.index),
        self.show_neighbor(show, true).map(i => show.route[i]),
        show.from,
      ] {
      if i is Some(i) {
        let slide = self.slides[i]
        let fragments : Array[(String, Array[@layout.PositionedPrimitive])] = []
        let (page, geometry, diagnostics) = paint_slide(
          slide,
          self.width,
          self.height,
          probe,
          profile,
          self.tile_sizes(slide),
          parts=if role == 2 ||
            (
              role == 0 &&
              (
                !show.animations.is_empty() ||
                slide.objects.any(object => object.media is Some(_))
              )
            ) {
            Some(fragments)
          } else {
            None
          },
        )
        if role == 0 {
          texts.append(geometry)
        }
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
              links: [],
              pages: [{ ..page, primitives, }],
              fonts: probe.font_info(),
            }
            (
              id,
              media_fragment(
                slide.objects.iter().find_first(object => object.id == id),
                document.drawing(images, clear=id.is_empty())[0].commands,
              ),
            )
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
      links: [],
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
      id: 0,
      previous: None,
      frame: show,
      key,
      regions: document.drawing(images),
      parts,
      images: resources,
      texts,
      links: self.show_links(self.slides[show.index], self.relationships()),
    }
    self.show_drawing = Some(drawing)
    drawing
  }
  let painted = drawing.regions.copy()
  painted[0] = ink_region(
    animated_region(
      painted[0],
      drawing.parts[0],
      show.animation_state(),
      self.slides[show.index],
    ),
    show.ink.get(show.index).unwrap_or([]),
    draft=show.ink_draft,
  )
  if show.from is Some(_) {
    let last = painted.length() - 1
    painted[last] = ink_region(
      animated_region(
        painted[last],
        drawing.parts[last],
        show.leaving,
        self.slides[show.from.unwrap()],
      ),
      show.ink.get(show.from.unwrap()).unwrap_or([]),
    )
  }
  let regions = [self.show_region(show, painted)]
  if self.show_neighbor(show, true) is Some(position) {
    regions.push(
      ink_region(
        drawing.regions[1],
        show.ink.get(show.route[position]).unwrap_or([]),
      ),
    )
  }
  guard self.sequence < 2147483647 else {
    @failure.reject("limit-exceeded", "Layout identity exhausted")
  }
  let (regions, media) = self.media_drawing(show, regions, images)
  self.sequence += 1
  self.showing = Some(show)
  self.show_drawing = Some({
    ..drawing,
    id: self.sequence,
    frame: show,
    previous: if drawing.id > 0 && drawing.frame.scene == show.scene {
      Some((drawing.id, drawing.frame))
    } else {
      None
    },
  })
  {
    "id": self.sequence,
    "revision": revision,
    "regions": regions,
    "outlines": probe.outline_resources(),
    "images": drawing.images,
    "links": show_link_query(drawing, show),
    "media": media,
    "animating": !show.paused &&
    (
      show.effect is Some(_) ||
      show.advance.after is Some(_) ||
      show.animations_running() ||
      show.pending_media_cues()
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
    for
      i in [
        Some(show.index),
        self.show_neighbor(show, true).map(i => show.route[i]),
        show.from,
      ] {
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
