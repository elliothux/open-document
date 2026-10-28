///|
fn extraction_rectangle(path : Array[@layout.PathSegment]) -> @layout.Border? {
  guard path is [Move(a, b), Line(c, d), Line(e, f), Line(g, h), Close] &&
    (a == c || b == d) &&
    (c == e || d == f) &&
    (e == g || f == h) &&
    (g == a || h == b) else {
    return None
  }
  let x = a.min(c).min(e).min(g)
  let y = b.min(d).min(f).min(h)
  let r = a.max(c).max(e).max(g)
  let t = b.max(d).max(f).max(h)
  if r <= x || t <= y {
    return Some({ x, y, width: 0, height: 0, })
  }
  Some({ x, y, width: r - x, height: t - y, })
}

///|
fn ContentContext::extraction_scope(
  self : ContentContext,
  command : @layout.DrawCommand,
) -> Unit {
  if self.extraction is Some(data) {
    data.clipScopes.push((data.clipBounds, data.complexClip))
    let clip = match command {
      ClipRect(rect) => Some(rect)
      ClipPath(path, _) => {
        let rectangle = extraction_rectangle(path)
        if rectangle is None {
          data.complexClip = true
        }
        rectangle
      }
      _ => None
    }
    if clip is Some(clip) {
      data.clipBounds = Some(
        match data.clipBounds {
          None => clip
          Some(previous) => {
            let x = previous.x.max(clip.x)
            let y = previous.y.max(clip.y)
            let r = (previous.x + previous.width).min(clip.x + clip.width)
            let t = (previous.y + previous.height).min(clip.y + clip.height)
            { x, y, width: (r - x).max(0), height: (t - y).max(0), }
          }
        },
      )
    }
  }
}

///|
fn ContentContext::extraction_restore(self : ContentContext) -> Unit {
  if self.extraction is Some(data) {
    if data.clipScopes.pop() is Some((bounds, complex)) {
      data.clipBounds = bounds
      data.complexClip = complex
    } else {
      data.complexClip = true
    }
  }
}

///|
fn ContentContext::extraction_clipped(
  self : ContentContext,
  points : Array[Double],
  margin~ : Double = 0,
) -> Bool {
  guard !points.is_empty() else { return false }
  guard self.extraction is Some(data) &&
    !data.complexClip &&
    points.length() % 2 == 0 else {
    return true
  }
  let page : @layout.Border = {
    x: 0,
    y: 0,
    width: self.page.width,
    height: self.page.height,
  }
  for rect in [Some(page), data.clipBounds] {
    if rect is Some(rect) {
      for i = 0; i < points.length(); i = i + 2 {
        if points[i] - margin < rect.x ||
          points[i] + margin > rect.x + rect.width ||
          points[i + 1] - margin < rect.y ||
          points[i + 1] + margin > rect.y + rect.height {
          return true
        }
      }
    }
  }
  false
}

///|
fn simple_image_form(bytes : Bytes) -> Bool raise {
  let ops = @pdflite.pdf_parse_content_ops_from_view(bytes)
  let mut images = 0
  for op in ops {
    match op {
      Op_Do(_) => images += 1
      Op_q | Op_Q | Op_cm(_) => ()
      _ => return false
    }
  }
  images == 1
}
