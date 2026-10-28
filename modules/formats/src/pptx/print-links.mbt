///|
fn print_link_rect(
  rect : @layout.Border,
  matrix : @layout.Matrix,
  page : Int32,
  width : Double,
  height : Double,
) -> @layout.SelectionRect? {
  let points = [
    (rect.x, rect.y),
    (rect.x + rect.width, rect.y),
    (rect.x, rect.y + rect.height),
    (rect.x + rect.width, rect.y + rect.height),
  ].map(point => matrix.point(point.0, point.1))
  let x = points
    .iter()
    .fold(init=width, (value, point) => value.min(point.0))
    .max(0)
  let y = points
    .iter()
    .fold(init=height, (value, point) => value.min(point.1))
    .max(0)
  let right = points
    .iter()
    .fold(init=0.0, (value, point) => value.max(point.0))
    .min(width)
  let bottom = points
    .iter()
    .fold(init=0.0, (value, point) => value.max(point.1))
    .min(height)
  if right > x && bottom > y {
    Some({ page, line: 0, x, y, width: right - x, height: bottom - y, })
  } else {
    None
  }
}

///|
fn Session::print_link_target(
  self : Session,
  slide : Slide,
  link : ShowLink,
  destinations : Map[String, Int32],
) -> @layout.LinkTarget? raise @failure.Failure {
  guard link.reason.is_empty() else {
    @failure.reject("unsupported-pdf", link.reason, part=slide.tree.part)
  }
  if link.kind == "external" {
    return Some(@layout.External(link.target))
  }
  if link.kind == "media" {
    return None
  }
  let target = if link.kind == "slide" {
    Some(link.target)
  } else if link.kind == "action" {
    let index = self.index(slide.tree.part)
    let destination = match link.target {
      "firstslide" => Some(0)
      "lastslide" => Some(self.slides.length() - 1)
      "nextslide" => Some((index + 1).min(self.slides.length() - 1))
      "previousslide" => Some((index - 1).max(0))
      _ => None
    }
    destination.map(index => self.slides[index].tree.part)
  } else {
    None
  }
  target
  .bind(target => destinations.get(target))
  .map(page => @layout.Internal(page, 0, 0))
}

///|
fn Session::print_links(
  self : Session,
  slide : Slide,
  texts : Array[TextGeometry],
  page : Int32,
  destinations : Map[String, Int32],
  relationships : ReadOnlyArray[@opc.Relationship],
  remaining : Int32,
) -> (Array[@layout.PageLink], Int32) raise @failure.Failure {
  let links : Array[@layout.PageLink] = []
  let geometry = Map::from_array(texts.map(text => (text.object, text)))
  let mut work = 0
  for link in self.show_links(slide, relationships) {
    if link.kind == "media" {
      continue
    }
    guard self.print_link_target(slide, link, destinations) is Some(target) else {
      continue
    }
    let object = link.object.geometry.unwrap()
    let (clip_matrix, clip) = link.object.text_clip(object)
    let clipping = if link.start < 0 {
      @layout.Matrix::identity()
    } else {
      clip_matrix
    }
    let frame = object.matrix.then(clipping)
    let bounds : Array[@layout.Border] = []
    if link.start < 0 {
      let pad = if object.width == 0 || object.height == 0 {
        link.object.line_width / 2
      } else {
        0.0
      }
      bounds.push({
        x: -pad,
        y: -pad,
        width: object.width + pad * 2,
        height: object.height + pad * 2,
      })
    } else if geometry.get(link.object.id) is Some(text) {
      let plane = frame.inverse().then(text.matrix)
      for line in text.lines {
        work += line.carets.length() + 1
        guard work <= remaining else {
          @failure.reject(
            "limit-exceeded", "Presentation PDF link geometry exceeds budget",
          )
        }
        let original_line = line
        let line = {
          ..line,
          cellClip: None,
          carets: line.carets.map(caret => {
            ..caret,
            before: caret.before + line.x,
            after: caret.after + line.x,
          }),
        }
        for rect in line.link_rects(link.start, link.end) {
          guard text.line_rect(original_line, rect) is Some(rect) else {
            continue
          }
          let left = if link.object.body.columns > 1 {
            rect.x.max(line.areaX)
          } else {
            rect.x
          }
          let right = if link.object.body.columns > 1 {
            (rect.x + rect.width).min(line.areaX + line.areaWidth)
          } else {
            rect.x + rect.width
          }
          if right > left &&
            print_link_rect(
              { ..rect, x: left, width: right - left, },
              plane,
              0,
              clip.width,
              clip.height,
            )
            is Some(clipped) {
            bounds.push({
              x: clipped.x,
              y: clipped.y,
              width: clipped.width,
              height: clipped.height,
            })
          }
        }
      }
    }
    for rect in bounds {
      if print_link_rect(rect, frame, page, self.width, self.height)
        is Some(rect) {
        guard links.length() < 65536 else {
          @failure.reject(
            "limit-exceeded", "Presentation PDF link rectangles exceed budget",
          )
        }
        links.push({ rect, target, })
      }
    }
  }
  (links, work)
}
