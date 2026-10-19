///|
priv struct ShowLink {
  object : Object
  start : Int
  end : Int
  label : String
  kind : String
  target : String
  reason : String
}

///|
fn Session::show_links(
  self : Session,
  slide : Slide,
) -> Array[ShowLink] raise @failure.Failure {
  let links = self.relationships()
  let result : Array[ShowLink] = []
  let mut units = 0
  for object in slide.objects {
    if object.geometry is None {
      continue
    }
    fn add(
      properties : Ref?,
      start : Int,
      end : Int,
      label : String,
    ) -> Unit raise @failure.Failure {
      guard properties.bind(p => p.child("hlinkClick")) is Some(_) else {
        return
      }
      let (kind, target, reason) = try {
        let value = self
          .read_hyperlink_at(properties, object.source.tree.part, links)
          .unwrap()
        (value.0, value.1, "")
      } catch {
        @failure.Failure(message~, ..) => ("", "", message)
      }
      let label = (if label.trim().is_empty() { object.name } else { label })
      .trim()
      .to_owned()[:1024].to_owned()
      let label = if label.is_empty() {
        if target.is_empty() {
          "Link"
        } else {
          target[:1024].to_owned()
        }
      } else {
        label
      }
      units += label.length() +
        reason.length() +
        (if kind == "external" { target.length() } else { 0 })
      guard result.length() < 4096 && units <= 1048576 else {
        @failure.reject("limit-exceeded", "Slideshow links exceed budget")
      }
      result.push({ object, start, end, label, kind, target, reason, })
    }
    let properties = hyperlink_properties(object)
    let click = properties.child("hlinkClick")
    if object.media is Some(media) &&
      (
        click is None ||
        click.unwrap().node.attribute("action") == Some("ppaction://media")
      ) {
      result.push({
        object,
        start: -1,
        end: -1,
        label: object.name,
        kind: "media",
        target: object.id,
        reason: if !media.reason.is_empty() {
          media.reason
        } else {
          object.diagnostic
        },
      })
    } else {
      add(Some(properties), -1, -1, object.name)
    }
    let mut offset = 0
    for paragraph in object.paragraphs {
      for run in paragraph.runs {
        if !run.text.is_empty() {
          add(
            run.source.bind(source => source.child("rPr")),
            offset,
            offset + run.text.length(),
            run.text,
          )
        }
        offset += run.text.length()
      }
      offset += 1
    }
  }
  result
}

///|
fn Session::invalidate_show_frame(self : Session) -> Unit {
  self.show_drawing = self.show_drawing.map(drawing => {
    ..drawing,
    id: 0,
    previous: None,
  })
}

///|
fn Session::current_show_frame(
  self : Session,
  id : Int,
) -> ShowDrawing raise @failure.Failure {
  guard self.showing is Some(current) &&
    self.show_drawing is Some(drawing) &&
    id > 0 &&
    drawing.id > 0 &&
    drawing.id == self.sequence &&
    current.scene == drawing.frame.scene &&
    current.position == drawing.frame.position &&
    current.route == drawing.frame.route else {
    @failure.reject(
      "stale-layout", "Slideshow interaction requires the displayed frame",
    )
  }
  if id == drawing.id {
    return drawing
  }
  if drawing.previous is Some((previous, frame)) &&
    previous == id &&
    frame.scene == current.scene {
    return { ..drawing, id, frame, }
  }
  @failure.reject(
    "stale-layout", "Slideshow interaction requires the displayed frame",
  )
}

///|
fn show_link_visible(link : ShowLink, show : ShowState) -> Bool {
  show.effect is None &&
  show
  .animation_state()
  .get(link.object.id)
  .map(value => value.opacity > 0)
  .unwrap_or(true)
}

///|
fn show_link_query(drawing : ShowDrawing, show : ShowState) -> Array[Json] {
  let values = show.animation_state()
  let result : Array[Json] = []
  for index, link in drawing.links {
    if link.kind == "media" ||
      show.effect is Some(_) ||
      values
      .get(link.object.id)
      .map(value => value.opacity <= 0)
      .unwrap_or(false) {
      continue
    } else {
      result.push({
        "id": index.to_string(),
        "label": link.label,
        "reason": link.reason,
        "external": if link.kind == "external" {
          Json(link.target)
        } else {
          Json::null()
        },
      })
    }
  }
  result
}

///|
fn show_text_link_hit(
  link : ShowLink,
  text : TextGeometry,
  x : Double,
  y : Double,
) -> Bool raise @failure.Failure {
  let (x, y) = text.matrix.inverse().point(x, y)
  for line in text.lines {
    if y < line.y || y > line.y + line.height {
      continue
    }
    for i in 0..<(line.carets.length() - 1) {
      let first = line.carets[i]
      let last = line.carets[i + 1]
      if first.offset < link.end &&
        last.offset > link.start &&
        x >= line.x + first.after.min(last.before) &&
        x <= line.x + first.after.max(last.before) {
        return true
      }
    }
  }
  false
}

///|
fn Session::show_link_hit(
  self : Session,
  drawing : ShowDrawing,
  x : Double,
  y : Double,
) -> Int? raise @failure.Failure {
  guard !x.is_nan() &&
    !x.is_inf() &&
    !y.is_nan() &&
    !y.is_inf() &&
    x >= 0 &&
    x <= self.width &&
    y >= 0 &&
    y <= self.height else {
    @failure.reject("invalid-hit", "Point is outside the slideshow page")
  }
  if drawing.frame.effect is Some(_) {
    return None
  }
  let slide = self.slides[drawing.frame.index]
  let values = drawing.frame.animation_state()
  for object in slide.objects.rev() {
    if object.kind == "group" || object.geometry is None {
      continue
    }
    let state = values.get(object.id).unwrap_or(ShowObject::initial())
    if state.opacity <= 0 {
      continue
    }
    let (px, py) = state.matrix(object).inverse().point(x, y)
    if !object_hit(object, px, py, 0) {
      continue
    }
    let text = drawing.texts.iter().find_first(text => text.object == object.id)
    for index, link in drawing.links {
      if link.object.id == object.id &&
        link.start >= 0 &&
        text is Some(text) &&
        show_text_link_hit(link, text, px, py) {
        return Some(index)
      }
    }
    let mut id = object.id
    for _ in 0..<32 {
      if drawing.links.search_by(link => link.object.id == id && link.start < 0)
        is Some(index) {
        return Some(index)
      }
      let parent = slide.object(id).parent
      if parent.is_empty() {
        break
      }
      id = parent
    }
    // An unlinked foreground object blocks links behind it.
    return None
  }
  None
}

///|
fn Session::apply_show_link(
  self : Session,
  drawing : ShowDrawing,
  index : Int,
  time : Double,
) -> Json raise @failure.Failure {
  guard drawing.links.get(index) is Some(link) &&
    show_link_visible(link, drawing.frame) else {
    @failure.reject(
      "invalid-operation", "Slideshow link is not currently visible",
    )
  }
  guard link.reason.is_empty() else {
    @failure.reject("protected-content", link.reason)
  }
  let current = self.showing.unwrap().advance(time)
  if link.kind == "media" {
    let media = current.media_state(link.target)
    let (next, sequence) = self.change_show_media(current, {
      object: link.target,
      token: media.token,
      action: if media.state == "playing" {
        "pause"
      } else {
        "play"
      },
      message: "",
    })
    let result = self.show_state(Some(next))
    self.showing = Some(next)
    self.media_sequence = sequence
    return result
  }
  let mut external : String? = None
  let show = if link.kind == "external" {
    external = Some(link.target)
    Some(current)
  } else if link.kind == "action" && link.target == "endshow" {
    None
  } else {
    let mut route = current.route
    let mut custom = current.custom
    let position = if link.kind == "slide" {
      let target = self.index(link.target)
      if route.search(target) is Some(position) {
        Some(position)
      } else {
        // Explicit links outside a configured show continue in the full presentation.
        route = Array::makei(self.slides.length(), i => i)
        custom = None
        Some(target)
      }
    } else if link.target == "lastslideviewed" {
      match current.last_view {
        Some((previous_route, position, previous_custom)) => {
          route = previous_route
          custom = previous_custom
          Some(position)
        }
        None => Some(current.position)
      }
    } else {
      match link.target {
        "firstslide" => self.show_neighbor(current, true, position=-1)
        "lastslide" =>
          self.show_neighbor(current, false, position=route.length())
        "nextslide" => self.show_neighbor(current, true)
        "previousslide" =>
          Some(self.show_neighbor(current, false).unwrap_or(current.position))
        _ =>
          @failure.reject("invalid-operation", "Unknown slideshow link action")
      }
    }
    position.map(position => {
      if route == current.route &&
        position == current.position &&
        !(current.cycling && link.target == "nextslide") {
        current
      } else {
        self.show_scene(
          route,
          position,
          custom,
          Some(current.index),
          time,
          true,
          leaving=current.animation_state(),
          last_view=Some((current.route, current.position, current.custom)),
        )
      }
    })
  }
  let result = self.show_state(show, external~)
  self.showing = show
  self.invalidate_show_frame()
  if show is None {
    self.show_drawing = None
  }
  result
}
