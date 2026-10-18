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
fn ShowState::animation_state(self : ShowState) -> Map[String, ShowObject] {
  let values : Map[String, ShowObject] = Map([])
  let visible : Map[String, Bool] = Map([])
  let alpha : Map[String, Double] = Map([])
  let classes : Map[String, Bool] = Map([])
  for item in self.animations {
    if !values.contains(item.object) {
      alpha[item.object] = 1
      values[item.object] = ShowObject::initial()
    }
    if ["appear", "disappear", "fadeIn", "fadeOut", "flyIn", "flyOut"].contains(
        item.kind,
      ) &&
      !visible.contains(item.object) {
      visible[item.object] = !["appear", "fadeIn", "flyIn"].contains(item.kind)
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
    let entrance = ["appear", "fadeIn", "flyIn"].contains(item.kind)
    let visibility = [
      "appear", "disappear", "fadeIn", "fadeOut", "flyIn", "flyOut",
    ].contains(item.kind)
    if visibility &&
      classes.get(item.object) is Some(previous) &&
      previous != entrance {
      visible[item.object] = true
      alpha[item.object] = 1
    }
    if visibility {
      classes[item.object] = entrance
    }
    let state = values[item.object]
    match item.kind {
      "appear" => visible[item.object] = true
      "disappear" => visible[item.object] = false
      "fadeIn" => {
        visible[item.object] = true
        alpha[item.object] = progress
      }
      "fadeOut" => alpha[item.object] = 1 - progress
      "scale" =>
        values[item.object] = {
          ..state,
          sx: 1 + (item.params[0] / 100 - 1) * progress,
          sy: 1 + (item.params[1] / 100 - 1) * progress,
        }
      "rotate" =>
        values[item.object] = { ..state, rotation: item.params[0] * progress, }
      "move" =>
        values[item.object] = {
          ..state,
          x: item.params[0] * progress,
          y: item.params[1] * progress,
        }
      "flyIn" => {
        let (x, y) = self.flights[i]
        visible[item.object] = true
        values[item.object] = {
          ..state,
          x: x * (1 - progress),
          y: y * (1 - progress),
        }
      }
      "flyOut" => {
        let (x, y) = self.flights[i]
        let direction = item.params[0].to_int()
        values[item.object] = {
          ..state,
          x: if (direction & 10) != 0 {
            state.x + (x - state.x) * progress
          } else {
            state.x
          },
          y: if (direction & 5) != 0 {
            state.y + (y - state.y) * progress
          } else {
            state.y
          },
        }
        if progress >= 1 - 1.0 / item.duration.to_double() {
          visible[item.object] = false
        }
      }
      _ => ()
    }
  }
  for object, shown in visible {
    values[object] = {
      ..values[object],
      opacity: if shown {
        alpha[object]
      } else {
        0
      },
    }
  }
  values
}

///|
fn ShowState::hidden_objects(self : ShowState) -> Array[String] {
  let values = self.animation_state()
  let result : Array[String] = []
  for item in self.animations {
    if values[item.object].opacity == 0 && !result.contains(item.object) {
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
fn ShowObject::matrix(self : ShowObject, object : Object) -> @layout.Matrix {
  let geometry = object.geometry.unwrap()
  let (cx, cy) = geometry.matrix.point(geometry.width / 2, geometry.height / 2)
  let rotation = self.rotation * @math.PI / 180
  let a = @math.cos(rotation) * self.sx
  let b = @math.sin(rotation) * self.sx
  let c = -@math.sin(rotation) * self.sy
  let d = @math.cos(rotation) * self.sy
  {
    a,
    b,
    c,
    d,
    e: cx + self.x - a * cx - c * cy,
    f: cy + self.y - b * cx - d * cy,
  }
}

///|
fn animated_region(
  page : @layout.DrawingRegion,
  parts : Array[(String, Array[@layout.DrawCommand])],
  state : Map[String, ShowObject],
  slide : Slide,
) -> @layout.DrawingRegion {
  guard !parts.is_empty() else { return page }
  let commands : Array[@layout.DrawCommand] = [
    ClipRect({ x: 0, y: 0, width: page.width, height: page.height, }),
  ]
  for (id, content) in parts {
    let value = state.get(id).unwrap_or(ShowObject::initial())
    let alpha = value.opacity
    let content = content[1:content.length() - 1].to_owned()
    let content : Array[@layout.DrawCommand] = if value.x != 0 ||
      value.y != 0 ||
      value.sx != 1 ||
      value.sy != 1 ||
      value.rotation != 0 {
      let object = slide.objects
        .iter()
        .find_first(object => object.id == id)
        .unwrap()
      [Transform(value.matrix(object)), ..content, Restore]
    } else {
      content
    }
    if alpha == 1 {
      commands.append(content)
    } else if alpha > 0 {
      commands.push(Layer(alpha, content))
    }
  }
  commands.push(Restore)
  { ..page, commands, }
}
