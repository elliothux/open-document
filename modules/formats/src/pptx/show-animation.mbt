///|
fn SlideAnimation::span(self : SlideAnimation) -> Double {
  (self.duration * self.repeat).to_double()
}

///|
fn ShowState::schedule_animations(self : ShowState, base : Double) -> ShowState {
  let starts = self.starts.copy()
  let mut group = base
  let mut end = base
  for i in self.step..<self.animations.length() {
    let item = self.animations[i]
    if i > self.step && item.trigger == "click" {
      break
    }
    if item.trigger == "after" {
      group = end
    }
    let start = group + item.delay.to_double()
    starts.push(start)
    end = end.max(start + item.span())
  }
  { ..self, starts, step: starts.length(), ready: self.ready.max(end), }
}

///|
fn ShowState::animations_running(self : ShowState) -> Bool {
  for i, start in self.starts {
    if i >= self.finished && self.elapsed < start + self.animations[i].span() {
      return true
    }
  }
  false
}

///|
fn ShowState::finish_animations(self : ShowState) -> ShowState {
  { ..self, finished: self.step, ready: self.elapsed, }
}

///|
fn ShowState::animation_opacity(self : ShowState) -> Map[String, Double] {
  let values : Map[String, Double] = Map([])
  let visible : Map[String, Bool] = Map([])
  let alpha : Map[String, Double] = Map([])
  let classes : Map[String, Bool] = Map([])
  for item in self.animations {
    if !visible.contains(item.object) {
      visible[item.object] = !["appear", "fadeIn"].contains(item.kind)
      alpha[item.object] = 1
    }
  }
  // Later start times replace earlier opacity, retaining source order on ties.
  let order = Array::makei(self.starts.length(), i => i)
  order.sort_by((a, b) => {
    if a < self.finished && b >= self.finished {
      -1
    } else if b < self.finished && a >= self.finished {
      1
    } else if self.starts[a] < self.starts[b] {
      -1
    } else if self.starts[a] > self.starts[b] {
      1
    } else {
      a - b
    }
  })
  for i in order {
    let item = self.animations[i]
    let elapsed = self.elapsed - self.starts[i]
    if i >= self.finished && elapsed < 0 {
      continue
    }
    let progress = if i < self.finished || elapsed >= item.span() {
      1.0
    } else {
      let cycle = elapsed / item.duration.to_double()
      cycle - cycle.floor()
    }
    let entrance = ["appear", "fadeIn"].contains(item.kind)
    if classes.get(item.object) is Some(previous) && previous != entrance {
      visible[item.object] = true
      alpha[item.object] = 1
    }
    classes[item.object] = entrance
    match item.kind {
      "appear" => visible[item.object] = true
      "disappear" => visible[item.object] = false
      "fadeIn" => {
        visible[item.object] = true
        alpha[item.object] = progress
      }
      _ => alpha[item.object] = 1 - progress
    }
  }
  for object, shown in visible {
    values[object] = if shown { alpha[object] } else { 0 }
  }
  values
}

///|
fn ShowState::hidden_objects(self : ShowState) -> Array[String] {
  let values = self.animation_opacity()
  let result : Array[String] = []
  for item in self.animations {
    if values[item.object] == 0 && !result.contains(item.object) {
      result.push(item.object)
    }
  }
  result
}

///|
fn ShowState::finish_entry(self : ShowState) -> ShowState {
  let shift = self.elapsed - self.settled
  {
    ..self,
    from: None,
    effect: None,
    settled: self.elapsed,
    starts: self.starts.map(time => time + shift),
    ready: if self.starts.is_empty() {
      0
    } else {
      self.ready + shift
    },
  }
}

///|
fn animated_region(
  page : @layout.DrawingRegion,
  parts : Array[(String, Array[@layout.DrawCommand])],
  opacity : Map[String, Double],
) -> @layout.DrawingRegion {
  guard !parts.is_empty() else { return page }
  let commands : Array[@layout.DrawCommand] = []
  for (id, content) in parts {
    let alpha = opacity.get(id).unwrap_or(1)
    if alpha == 1 {
      commands.append(content)
    } else if alpha > 0 {
      commands.push(Layer(alpha, content))
    }
  }
  { ..page, commands, }
}
