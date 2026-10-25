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
  if object.body.upright && !object.paragraphs.is_empty() {
    let (matrix, clip) = object.text_clip(geometry)
    let (tx, ty) = geometry.matrix.then(matrix).inverse().point(x, y)
    if tx >= clip.x &&
      tx <= clip.x + clip.width &&
      ty >= clip.y &&
      ty <= clip.y + clip.height {
      return true
    }
  }
  let (x, y) = geometry.matrix.inverse().point(x, y)
  let width = geometry.width
  let height = geometry.height
  let margin = tolerance + object.line_width / 2
  if line_shape(object.preset) && object.line_end_hit(geometry, x, y, margin) {
    return true
  }
  let bounds = if line_shape(object.preset) && object.cap == "sq" {
    margin * 1.4142135623730951
  } else {
    margin
  }
  if !polygon_shape(object.preset) &&
    (x < -bounds || y < -bounds || x > width + bounds || y > height + bounds) {
    return false
  }
  if !object.diagnostic.is_empty() ||
    object.kind == "image" ||
    object.kind == "group" ||
    (
      !object.paragraphs.is_empty() &&
      !object.has_fill() &&
      object.stroke.is_empty()
    ) {
    return x >= 0 && y >= 0 && x <= width && y <= height
  }
  if curved_connector(object.preset) {
    return object.curve_hit(geometry, x, y, margin)
  }
  if !object.polyline.is_empty() {
    return object.polyline_hit(geometry, x, y, margin)
  }
  if line_shape(object.preset) {
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
    if object.has_fill() {
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
  if object.has_fill() {
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
  let mut offset = 0
  let mut distance = 1.0e30
  let mut column_distance = 1.0e30
  for line in text.lines {
    let (x, y) = text.line_matrix(line).inverse().point(x, y)
    let dx = (line.areaX - x).max(0).max(x - line.areaX - line.areaWidth)
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
        if dx < column_distance || (dx == column_distance && score < distance) {
          column_distance = dx
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
  text~ : Bool = false,
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
  let context = if self.selection.mode == "object" &&
    !self.selection.object.is_empty() {
    slide.object(self.selection.object).parent
  } else {
    ""
  }
  guard slide.read_only.is_empty() else {
    @failure.reject("protected-content", slide.read_only)
  }
  for top in slide.objects.rev() {
    let mut object = top
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
          if text &&
            child.text_reason.is_empty() &&
            !child.paragraphs.is_empty() {
            object = child
          } else if !context.is_empty() {
            let mut target = child
            while !target.parent.is_empty() && target.parent != context {
              target = slide.object(target.parent)
            }
            if target.parent == context {
              object = target
            }
          }
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
        "offset": text
        .map(text => {
          if object.table is Some(_) {
            object.table_hit_offset(text, x, y)
          } else {
            closest_caret(text, x, y)
          }
        })
        .unwrap_or(0),
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
  grid_scale~ : Double? = None,
) -> Json raise @failure.Failure {
  let view = self.current_view(id)
  let selection = self.candidate
    .map(item => item.selection)
    .unwrap_or(self.selection)
  let slide = self.current()
  let same_parent = selection.objects.all(id => {
    slide.object(id).parent == slide.object(selection.object).parent
  })
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
    let cells = object.table.map(table => table.range(selection))
    if selection.mode == "text" && cells is Some(range) && range.multiple() {
      rects.push(object.table_range_polygon(range))
    } else if selection.mode == "text" &&
      view.texts.iter().find_first(text => text.object == selection.object)
      is Some(text) {
      let a = selection.anchor.min(selection.focus)
      let b = selection.anchor.max(selection.focus)
      for line in text.lines {
        let matrix = text.line_matrix(line)
        if line.carets
          .iter()
          .find_first(caret => caret.offset == selection.focus)
          is Some(position) {
          let (x, y) = matrix.point(line.x + position.after, line.y)
          let (end_x, end_y) = matrix.point(
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
            if right > left &&
              text.line_rect(line, {
                x: line.x + left,
                y: line.y,
                width: right - left,
                height: line.height,
              })
              is Some(rect) {
              rects.push(
                polygon(text.matrix, rect.x, rect.y, rect.width, rect.height),
              )
            }
          }
        }
      }
    }
  }
  if selection.objects.length() > 1 {
    let box = slide.selection_box(selection.objects, in_parent=same_parent)
    outline = polygon(
      if same_parent {
        slide.object(selection.object).source.parent_frame()
      } else {
        @layout.Matrix::identity()
      },
      box.x,
      box.y,
      box.width,
      box.height,
    )
  }
  {
    "layoutId": id,
    "grid": self.grid_geometry(grid_scale),
    "snapLines": self.snap_lines(),
    "snapSpacing": self.snap_spacing(),
    "snapSize": self.snap_size(),
    "revision": self.revision,
    "outline": outline,
    "outlines": outlines,
    "adjustmentHandles": self.adjustment_geometry(),
    "handles": if selection.mode == "object" &&
      selection.objects.length() == 1 &&
      slide.object(selection.object).source.node.name == "cxnSp" &&
      self
      .object_edit_reason(slide.object(selection.object), "endpoints")
      .is_empty() {
      let (start, end) = slide.object(selection.object).connector_ends()
      [{ "x": start.x, "y": start.y }, { "x": end.x, "y": end.y }]
    } else if selection.mode == "object" &&
      same_parent &&
      selection.objects.all(id => {
        let object = slide.object(id)
        object.geometry is Some(_) &&
        self.object_edit_reason(object, "transform").is_empty()
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
  let orientation = if object.table is Some(table) {
    let (r, c) = table.cell_at(self.selection.focus)
    table.rows[r].cells[c].body.direction
  } else {
    object.body.direction
  }
  let direction = match (orientation, direction) {
    ("vert", "left") | ("vert270", "right") => "down"
    ("vert", "right") | ("vert270", "left") => "up"
    ("vert", "up") | ("vert270", "down") => "left"
    ("vert", "down") | ("vert270", "up") => "right"
    _ => direction
  }
  if !extend_selection &&
    self.selection.anchor != self.selection.focus &&
    ["left", "right"].contains(direction) {
    let focus = if direction == "left" {
      self.selection.anchor.min(self.selection.focus)
    } else {
      self.selection.anchor.max(self.selection.focus)
    }
    return self.select(
      revision,
      self.selection.slide,
      object.id,
      "text",
      focus,
      focus,
    )
  }
  let text = object.text()
  let boundaries = @layout.grapheme_boundaries(text)
  let index = boundaries.search(self.selection.focus).unwrap()
  let mut focus = self.selection.focus
  let table_focus = if object.table is Some(table) &&
    table.rtl &&
    orientation == "horz" {
    view.texts
    .iter()
    .find_first(text => text.object == object.id)
    .bind(text => table.rtl_navigation(text, focus, direction))
  } else {
    None
  }
  if table_focus is Some(position) {
    focus = position
  } else {
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
                let column = if object.table is None && object.body.columns > 1 {
                  line.areaX - next.areaX
                } else {
                  0.0
                }
                let gap = (position.after +
                next.x -
                caret.after -
                line.x +
                column).abs()
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
        @failure.reject(
          "invalid-operation", "Unknown text navigation direction",
        )
    }
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
