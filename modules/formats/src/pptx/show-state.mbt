///|
priv struct ShowState {
  index : Int
  from : Int?
  effect : SlideTransition?
  time : Double
  elapsed : Double
  paused : Bool
}

///|
priv struct ShowDrawing {
  key : String
  regions : Array[@layout.DrawingRegion]
  images : Array[String]
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
) -> Json raise @failure.Failure {
  if show is Some(show) {
    let slide = self.slides[show.index]
    let text = slide.objects.map(object => object.text()).join("\n")
    guard text.length() <= 1048576 else {
      @failure.reject("limit-exceeded", "Slideshow text exceeds budget")
    }
    {
      "active": true,
      "revision": self.revision,
      "slide": slide.tree.part,
      "index": show.index,
      "count": self.slides.length(),
      "text": text,
      "paused": show.paused,
      "nextSlide": self
      .show_neighbor(show.index, true)
      .map(i => Json(self.slides[i].tree.part))
      .unwrap_or(Json::null()),
      "notes": self.notes_query(slide.tree.part),
    }
  } else {
    {
      "active": false,
      "revision": self.revision,
      "slide": Json::null(),
      "index": -1,
      "count": self.slides.length(),
      "text": "",
      "paused": false,
      "nextSlide": Json::null(),
      "notes": { "text": "", "reason": "" },
    }
  }
}

///|
fn Session::show_scene(
  self : Session,
  index : Int,
  from : Int?,
  time : Double,
  animated : Bool,
) -> ShowState raise @failure.Failure {
  let transition = if animated {
    read_slide_transition(self.slides[index].tree)
  } else {
    None
  }
  let effect = match transition {
    Some(value) if value.kind != "none" => Some(value)
    _ => None
  }
  {
    index,
    from: if effect is Some(_) {
      from
    } else {
      None
    },
    effect,
    time,
    elapsed: 0,
    paused: false,
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
