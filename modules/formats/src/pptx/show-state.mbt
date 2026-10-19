///|
priv struct ShowState {
  scene : Double
  index : Int
  route : Array[Int]
  position : Int
  custom : String?
  last_view : (Array[Int], Int, String?)?
  cycling : Bool
  from : Int?
  effect : SlideTransition?
  time : Double
  elapsed : Double
  paused : Bool
  advance : SlideAdvance
  settled : Double
  animations : Array[SlideAnimation]
  flights : Array[(Double, Double)]
  starts : Array[Double]
  finished : Int
  step : Int
  ready : Double
  leaving : Map[String, ShowObject]
  ink : Map[Int, Array[ShowInkStroke]]
  ink_strokes : Int
  ink_points : Int
  ink_draft : ShowInkStroke?
  media : Map[String, ShowMediaPlayback]
}

///|
priv struct ShowObject {
  opacity : Double
  x : Double
  y : Double
  sx : Double
  sy : Double
  rotation : Double
}

///|
fn ShowObject::initial() -> ShowObject {
  { opacity: 1, x: 0, y: 0, sx: 1, sy: 1, rotation: 0, }
}

///|
priv struct ShowDrawing {
  id : Int
  previous : (Int, ShowState)?
  frame : ShowState
  key : String
  regions : Array[@layout.DrawingRegion]
  parts : Array[Array[(String, Array[@layout.DrawCommand])]]
  images : Array[String]
  texts : Array[TextGeometry]
  links : Array[ShowLink]
}

///|
fn show_time(value : Double) -> Unit raise @failure.Failure {
  guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 1000000000 else {
    @failure.reject("invalid-operation", "Invalid slideshow time")
  }
}

///|
fn ShowState::advance(
  self : ShowState,
  time : Double,
) -> ShowState raise @failure.Failure {
  show_time(time)
  guard time >= self.time else {
    @failure.reject("invalid-operation", "Slideshow time cannot move backwards")
  }
  let elapsed = self.elapsed +
    (if self.paused { 0.0 } else { time - self.time })
  if self.effect is Some(effect) && elapsed >= effect.duration.to_double() {
    { ..self, time, elapsed, effect: None, from: None, }
  } else {
    { ..self, time, elapsed, }
  }
}

///|
fn Session::show_state(
  self : Session,
  show : ShowState?,
  external~ : String? = None,
) -> Json raise @failure.Failure {
  if show is Some(show) {
    let slide = self.slides[show.index]
    let hidden = show.hidden_objects()
    let text = slide.objects
      .filter(object => !hidden.contains(object.id))
      .map(object => object.text())
      .join("\n")
    guard text.length() <= 1048576 else {
      @failure.reject("limit-exceeded", "Slideshow text exceeds budget")
    }
    {
      "active": true,
      "external": external.map(value => Json(value)).unwrap_or(Json::null()),
      "revision": self.revision,
      "slide": slide.tree.part,
      "index": show.index,
      "order": show.route.map(index => self.slides[index].tree.part),
      "position": show.position,
      "custom": show.custom.map(value => Json(value)).unwrap_or(Json::null()),
      "count": self.slides.length(),
      "text": text,
      "paused": show.paused,
      "media": self.show_media_query(show),
      "step": show.step,
      "steps": show.animations.length(),
      "ink": {
        "strokes": show.ink.get(show.index).unwrap_or([]).length(),
        "points": show.ink
        .get(show.index)
        .unwrap_or([])
        .fold(init=0, (sum, stroke) => sum + stroke.points.length()) +
        show.ink_draft.map(stroke => stroke.points.length()).unwrap_or(0),
        "drawing": show.ink_draft is Some(_),
      },
      "nextSlide": self
      .show_neighbor(show, true)
      .map(i => Json(self.slides[show.route[i]].tree.part))
      .unwrap_or(Json::null()),
      "notes": self.notes_query(slide.tree.part),
    }
  } else {
    {
      "active": false,
      "external": Json::null(),
      "revision": self.revision,
      "slide": Json::null(),
      "index": -1,
      "order": [],
      "position": -1,
      "custom": Json::null(),
      "count": self.slides.length(),
      "text": "",
      "paused": false,
      "media": [],
      "step": 0,
      "steps": 0,
      "ink": { "strokes": 0, "points": 0, "drawing": false },
      "nextSlide": Json::null(),
      "notes": { "text": "", "reason": "" },
    }
  }
}

///|
fn Session::show_scene(
  self : Session,
  route : Array[Int],
  position : Int,
  custom : String?,
  from : Int?,
  time : Double,
  animated : Bool,
  leaving~ : Map[String, ShowObject] = Map([]),
  last_view~ : (Array[Int], Int, String?)? = None,
) -> ShowState raise @failure.Failure {
  let index = route[position]
  let transition = if animated {
    read_slide_transition(self.slides[index].tree)
  } else {
    None
  }
  let effect = match transition {
    Some(value) if value.kind != "none" => Some(value)
    _ => None
  }
  let advance = read_slide_advance(self.slides[index].tree)
  let settings = self.read_show_settings()
  let animations = if settings.animations {
    self.read_animations(self.slides[index])
  } else {
    []
  }
  let show : ShowState = {
    scene: time,
    index,
    route,
    position,
    custom,
    last_view,
    cycling: settings.cycling,
    from: if effect is Some(_) {
      from
    } else {
      None
    },
    effect,
    time,
    elapsed: 0,
    paused: false,
    advance: if settings.timings {
      advance
    } else {
      { ..advance, after: None, }
    },
    settled: effect.map(v => v.duration.to_double()).unwrap_or(0),
    animations,
    flights: self.flight_offsets(self.slides[index], animations),
    starts: [],
    finished: 0,
    step: 0,
    ready: 0,
    leaving: if effect is Some(_) {
      leaving
    } else {
      Map([])
    },
    ink: self.showing.map(show => show.ink).unwrap_or(Map([])),
    ink_strokes: self.showing.map(show => show.ink_strokes).unwrap_or(0),
    ink_points: self.showing.map(show => show.ink_points).unwrap_or(0),
    ink_draft: None,
    media: Map([]),
  }
  if show.animations.get(0) is Some(item) && item.trigger != "click" {
    show.schedule_animations(show.settled)
  } else {
    show
  }
}

///|
fn Session::show_region(
  self : Session,
  show : ShowState,
  regions : Array[@layout.DrawingRegion],
) -> @layout.DrawingRegion {
  let current = regions[0]
  guard show.effect is Some(effect) else { return current }
  let previous : @layout.DrawingRegion = if show.from is Some(_) {
    regions.last().unwrap()
  } else {
    {
      ..current,
      commands: [
        FillRect({
          x: 0,
          y: 0,
          width: self.width,
          height: self.height,
          color: "000000",
        }),
      ],
    }
  }
  let progress = (show.elapsed / effect.duration.to_double()).max(0).min(1)
  if effect.kind == "fade" {
    return {
      ..current,
      commands: [..previous.commands, Layer(progress, current.commands)],
    }
  }
  let (x, y) = match effect.direction {
    "left" => (-self.width, 0.0)
    "right" => (self.width, 0.0)
    "up" => (0.0, -self.height)
    _ => (0.0, self.height)
  }
  {
    ..current,
    commands: [
      ClipRect({ x: 0, y: 0, width: self.width, height: self.height, }),
      Transform({
        ..@layout.Matrix::identity(),
        e: x * progress,
        f: y * progress,
      }),
      ..previous.commands,
      Restore,
      Transform({
        ..@layout.Matrix::identity(),
        e: x * (progress - 1),
        f: y * (progress - 1),
      }),
      ..current.commands,
      Restore,
      Restore,
    ],
  }
}
