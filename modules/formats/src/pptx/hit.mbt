///|
fn Session::current_view(
  self : Session,
  id : Int,
) -> View raise @failure.Failure {
  self.check()
  guard self.view is Some(view) &&
    view.id == id &&
    view.revision == self.revision &&
    view.slide == self.selection.slide else {
    @failure.reject(
      "stale-layout", "PPTX geometry requires the displayed layout",
    )
  }
  view
}

///|
fn object_hit(
  object : Object,
  x : Double,
  y : Double,
  tolerance : Double,
) -> Bool raise @failure.Failure {
  guard object.geometry is Some(geometry) else { return true }
  let (x, y) = geometry.matrix.inverse().point(x, y)
  let width = geometry.width
  let height = geometry.height
  let margin = tolerance + object.line_width / 2
  let bounds = if object.preset == "line" && object.cap == "sq" {
    margin * 1.4142135623730951
  } else {
    margin
  }
  if x < -bounds || y < -bounds || x > width + bounds || y > height + bounds {
    return false
  }
  if !object.diagnostic.is_empty() ||
    object.kind == "image" ||
    object.kind == "group" ||
    (
      !object.paragraphs.is_empty() &&
      object.fill.is_empty() &&
      object.gradient is None &&
      object.stroke.is_empty()
    ) {
    return x >= 0 && y >= 0 && x <= width && y <= height
  }
  if object.preset == "line" {
    let square = width * width + height * height
    let dot = x * width + y * height
    if square > 0 && object.cap != "rnd" {
      let cross = x * height - y * width
      let extension = if object.cap == "sq" { margin } else { tolerance }
      return cross * cross <= margin * margin * square &&
        (dot >= 0 || dot * dot <= extension * extension * square) &&
        (
          dot <= square ||
          (dot - square) * (dot - square) <= extension * extension * square
        )
    }
    let t = if square > 0 {
      ((x * width + y * height) / square).max(0).min(1)
    } else {
      0.0
    }
    return (x - t * width) * (x - t * width) +
      (y - t * height) * (y - t * height) <=
      margin * margin
  }
  if object.preset == "ellipse" {
    if width <= 0 || height <= 0 {
      return false
    }
    let value = (2.0 * x / width - 1) * (2.0 * x / width - 1) +
      (2.0 * y / height - 1) * (2.0 * y / height - 1)
    if !object.fill.is_empty() || object.gradient is Some(_) {
      return value <= 1
    }
    let outer = 1.0 + 2.0 * margin / width.min(height)
    let inner = (1.0 - 2.0 * margin / width.min(height)).max(0)
    return !object.stroke.is_empty() &&
      value <= outer * outer &&
      value >= inner * inner
  }
  if object.preset == "roundRect" ||
    arrow_shape(object.preset) ||
    polygon_shape(object.preset) {
    return object.preset_hit(geometry, x, y, margin)
  }
  if !object.fill.is_empty() || object.gradient is Some(_) {
    return x >= 0 && y >= 0 && x <= width && y <= height
  }
  !object.stroke.is_empty() &&
  (
    x.abs() <= margin ||
    y.abs() <= margin ||
    (x - width).abs() <= margin ||
    (y - height).abs() <= margin
  )
}

///|
fn closest_caret(
  text : TextGeometry,
  x : Double,
  y : Double,
) -> Int raise @failure.Failure {
  let (x, y) = text.matrix.inverse().point(x, y)
  let mut offset = 0
  let mut distance = 1.0e30
  for line in text.lines {
    let dy = if y < line.y {
      line.y - y
    } else if y > line.y + line.height {
      y - line.y - line.height
    } else {
      0.0
    }
    for caret in line.carets {
      for edge in [caret.before, caret.after] {
        let score = dy * dy * 10000 + (x - line.x - edge) * (x - line.x - edge)
        if score < distance {
          distance = score
          offset = caret.offset
        }
      }
    }
  }
  offset
}

///|
pub fn Session::hit(
  self : Session,
  id : Int,
  x : Double,
  y : Double,
  tolerance : Double,
) -> Json raise @failure.Failure {
  let view = self.current_view(id)
  guard !x.is_nan() &&
    !x.is_inf() &&
    !y.is_nan() &&
    !y.is_inf() &&
    tolerance >= 0 &&
    tolerance <= 72 else {
    @failure.reject("invalid-hit", "Invalid point or tolerance")
  }
  let slide = self.current()
  guard slide.read_only.is_empty() else {
    @failure.reject("protected-content", slide.read_only)
  }
  for object in slide.objects.rev() {
    if !object.parent.is_empty() {
      continue
    }
    let hit = if object.kind == "group" && object.diagnostic.is_empty() {
      let mut found = false
      for child in slide.objects.rev() {
        if child.kind != "group" &&
          child.source.tree.part == object.source.tree.part &&
          child.source.node.start > object.source.node.start &&
          child.source.node.end < object.source.node.end &&
          object_hit(child, x, y, tolerance) {
          found = true
          break
        }
      }
      found
    } else {
      object_hit(object, x, y, tolerance)
    }
    if hit {
      let text = view.texts.iter().find_first(text => text.object == object.id)
      return {
        "object": object.id,
        "offset": text.map(text => closest_caret(text, x, y)).unwrap_or(0),
        "readOnlyReason": object.read_only,
        "textReadOnlyReason": object.text_reason,
      }
    }
  }
  { "object": "", "offset": 0, "readOnlyReason": "", "textReadOnlyReason": "" }
}

///|
fn polygon(
  matrix : @layout.Matrix,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Array[Json] {
  [(x, y), (x + width, y), (x + width, y + height), (x, y + height)].map(point => {
    let (x, y) = matrix.point(point.0, point.1)
    let result : Json = { "x": x, "y": y }
    result
  })
}

///|
pub fn Session::selection_geometry(
  self : Session,
  id : Int,
) -> Json raise @failure.Failure {
  let view = self.current_view(id)
  let selection = self.candidate
    .map(item => item.selection)
    .unwrap_or(self.selection)
  let slide = self.current()
  let mut outline : Array[Json] = []
  let outlines : Array[Array[Json]] = []
  let rects : Array[Array[Json]] = []
  let mut caret : Json = Json::null()
  for id in selection.objects {
    if slide.object(id).geometry is Some(g) {
      outlines.push(polygon(g.matrix, 0, 0, g.width, g.height))
    }
  }
  if !selection.object.is_empty() {
    let object = slide.object(selection.object)
    if object.geometry is Some(geometry) {
      outline = polygon(geometry.matrix, 0, 0, geometry.width, geometry.height)
    }
    if selection.mode == "text" &&
      view.texts.iter().find_first(text => text.object == selection.object)
      is Some(text) {
      let a = selection.anchor.min(selection.focus)
      let b = selection.anchor.max(selection.focus)
      for line in text.lines {
        if line.carets
          .iter()
          .find_first(caret => caret.offset == selection.focus)
          is Some(position) {
          let (x, y) = text.matrix.point(line.x + position.after, line.y)
          let (end_x, end_y) = text.matrix.point(
            line.x + position.after,
            line.y + line.height,
          )
          caret = {
            "x": x,
            "y": y,
            "endX": end_x,
            "endY": end_y,
            "height": line.height,
          }
        }
        for index in 0..<(line.carets.length() - 1) {
          let first = line.carets[index]
          let last = line.carets[index + 1]
          if first.offset >= a && last.offset <= b && first.offset < last.offset {
            let left = first.after.min(last.before)
            let right = first.after.max(last.before)
            if right > left {
              rects.push(
                polygon(
                  text.matrix,
                  line.x + left,
                  line.y,
                  right - left,
                  line.height,
                ),
              )
            }
          }
        }
      }
    }
  }
  if selection.objects.length() > 1 {
    let box = slide.selection_box(selection.objects)
    outline = polygon(
      @layout.Matrix::identity(),
      box.x,
      box.y,
      box.width,
      box.height,
    )
  }
  {
    "layoutId": id,
    "revision": self.revision,
    "outline": outline,
    "outlines": outlines,
    "handles": if selection.mode == "object" &&
      selection.objects.all(id => {
        let object = slide.object(id)
        object.geometry is Some(_) &&
        self.object_edit_reason(object, "arrange").is_empty()
      }) {
      outline
    } else {
      []
    },
    "rects": rects,
    "caret": caret,
  }
}

///|
pub fn Session::navigate(
  self : Session,
  revision : Int,
  id : Int,
  direction : String,
  extend_selection : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let view = self.current_view(id)
  let current = self.current()
  if self.selection.mode == "object" {
    guard ["next", "previous"].contains(direction) else {
      @failure.reject(
        "invalid-operation", "Object navigation requires next or previous",
      )
    }
    let objects = current.objects.filter(object => object.parent.is_empty())
    if objects.is_empty() {
      return self.query()
    }
    let mut index = if direction == "next" { -1 } else { 0 }
    for i, object in objects {
      if object.id == self.selection.object {
        index = i
        break
      }
    }
    index = (
        index + (if direction == "next" { 1 } else { objects.length() - 1 })
      ) %
      objects.length()
    return self.select(
      revision,
      self.selection.slide,
      objects[index].id,
      "object",
      0,
      0,
    )
  }
  let object = current.object(self.selection.object)
  let text = object.text()
  let boundaries = @layout.grapheme_boundaries(text)
  let index = boundaries.search(self.selection.focus).unwrap()
  let mut focus = self.selection.focus
  match direction {
    "left" => focus = boundaries[(index - 1).max(0)]
    "right" => focus = boundaries[(index + 1).min(boundaries.length() - 1)]
    "home" => focus = 0
    "end" => focus = text.length()
    "up" | "down" =>
      if view.texts.iter().find_first(text => text.object == object.id)
        is Some(geometry) {
        for i, line in geometry.lines {
          if line.carets.iter().find_first(caret => caret.offset == focus)
            is Some(caret) {
            let target = (i + (if direction == "up" { -1 } else { 1 }))
              .max(0)
              .min(geometry.lines.length() - 1)
            let next = geometry.lines[target]
            let mut distance = 1.0e30
            for position in next.carets {
              let gap = (position.after + next.x - caret.after - line.x).abs()
              if gap < distance {
                focus = position.offset
                distance = gap
              }
            }
            break
          }
        }
      }
    _ =>
      @failure.reject("invalid-operation", "Unknown text navigation direction")
  }
  self.select(
    revision,
    self.selection.slide,
    object.id,
    "text",
    if extend_selection {
      self.selection.anchor
    } else {
      focus
    },
    focus,
  )
}
