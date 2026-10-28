///|
/// Resolves both axes to offsets in their existing reference frames.
pub fn Layout::drawing_anchor_offsets(
  self : Layout,
  page : PageSetup,
  paragraph : Int32,
  start : Int32,
) -> DrawingAnchor raise @failure.Failure {
  page.validate()
  for frame in self.pages {
    for line in frame.lines {
      if line.paragraph != paragraph {
        continue
      }
      for image in line.drawings {
        if image.start != start || image.anchor is None {
          continue
        }
        let anchor = image.anchor.unwrap()
        fn offset(
          axis : DrawingAxis,
          position : Double,
          horizontal : Bool,
        ) -> DrawingAxis {
          match axis {
            Offset(_, _) => axis
            Aligned(reference, _) => {
              let origin = image_axis_origin(
                axis, horizontal, page, frame, line,
              )
              Offset(reference, position - origin)
            }
          }
        }
        return {
          ..anchor,
          horizontal: offset(anchor.horizontal, image.x, true),
          vertical: offset(anchor.vertical, image.y, false),
        }
      }
    }
  }
  @failure.reject("invalid-image", "Floating picture has no placed frame")
}

///|
pub(all) enum DrawingAxis {
  Offset(String, Double)
  Aligned(String, String)
}

///|
pub impl ToJson for DrawingAxis with fn to_json(self) {
  match self {
    Offset(reference, value) =>
      { "relativeTo": reference, "offset": value, "align": Json::null() }
    Aligned(reference, value) =>
      { "relativeTo": reference, "offset": Json::null(), "align": value }
  }
}

///|
pub extend DrawingAxis with ToJson::{to_json}

///|
pub(all) struct DrawingAnchor {
  horizontal : DrawingAxis
  vertical : DrawingAxis
  behind : Bool
  order : Int64
  wrapping : String
  wrapSide : String
  distance : CellMargins
}

///|
pub impl ToJson for DrawingAnchor with fn to_json(self) {
  {
    "horizontal": self.horizontal,
    "vertical": self.vertical,
    "behind": self.behind,
    "order": self.order.to_double(),
    "wrapping": self.wrapping,
    "wrapSide": self.wrapSide,
    "distance": self.distance,
  }
}

///|
pub extend DrawingAnchor with ToJson::{to_json}

///|
fn DrawingAxis::validate(
  self : DrawingAxis,
  horizontal : Bool,
) -> Unit raise @failure.Failure {
  let reference = match self {
    Offset(reference, _) | Aligned(reference, _) => reference
  }
  guard (if horizontal {
    ["page", "margin", "column"]
  } else {
    ["page", "margin", "paragraph"]
  }).contains(reference) else {
    @failure.reject(
      "unsupported-layout", "Unsupported floating image reference",
    )
  }
  match self {
    Offset(_, value) => {
      guard !value.is_nan() && !value.is_inf() && value.abs() <= 14400 else {
        @failure.reject(
          "limit-exceeded", "Floating image offset exceeds drawing bounds",
        )
      }
    }
    Aligned(_, value) => {
      guard (if horizontal {
        ["left", "center", "right"]
      } else {
        ["top", "center", "bottom"]
      }).contains(value) else {
        @failure.reject(
          "unsupported-layout", "Unsupported floating image alignment",
        )
      }
    }
  }
}

///|
pub fn DrawingAnchor::validate(
  self : DrawingAnchor,
) -> Unit raise @failure.Failure {
  self.horizontal.validate(true)
  self.vertical.validate(false)
  guard self.order >= 0 && self.order <= 4294967295L else {
    @failure.reject("invalid-image", "Invalid floating image layer order")
  }
  guard ["none", "topBottom", "square"].contains(self.wrapping) &&
    ["bothSides", "left", "right", "largest"].contains(self.wrapSide) &&
    (self.wrapping == "square" || self.wrapSide == "bothSides") &&
    [
      self.distance.top,
      self.distance.right,
      self.distance.bottom,
      self.distance.left,
    ].all(value => {
      !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400
    }) else {
    @failure.reject(
      "invalid-image", "Invalid floating image wrapping or text distance",
    )
  }
}

///|
fn DrawingAxis::position(
  self : DrawingAxis,
  page : (Double, Double),
  margin : (Double, Double),
  region : (Double, Double),
  extent : Double,
) -> Double {
  let reference = match self {
    Offset(reference, _) | Aligned(reference, _) => reference
  }
  let (start, length) = match reference {
    "page" => page
    "margin" => margin
    _ => region
  }
  match self {
    Offset(_, value) => start + value
    Aligned("paragraph", _) => start
    Aligned(_, "center") => start + (length - extent) / 2
    Aligned(_, "right" | "bottom") => start + length - extent
    Aligned(_, _) => start
  }
}

///|
fn Flow::validate_floating_images(self : Flow) -> Unit raise @failure.Failure {
  let mut count = 0
  for paragraph in self.paragraphs {
    for span in paragraph.spans {
      if span.drawing is Some(image) && image.anchor is Some(anchor) {
        anchor.validate()
        count += 1
      }
    }
  }
  guard count <= 256 else {
    @failure.reject("limit-exceeded", "Floating image count exceeds256")
  }
  let other : Array[Paragraph] = []
  for table in self.tables {
    for row in table.rows {
      for cell in row {
        other.append(cell)
      }
    }
  }
  for stories in [self.headers, self.footers] {
    for story in stories.values() {
      other.append(story)
    }
  }
  guard !other.any(paragraph => {
    paragraph.spans.any(span => {
      span.drawing.bind(image => image.anchor) is Some(_)
    })
  }) else {
    @failure.reject(
      "unsupported-layout", "Floating images in tables headers or footers require layout support",
    )
  }
}

///|
fn PageFrame::floating_images(
  self : PageFrame,
) -> Array[(Int32, PlacedDrawingFrame)] {
  let result : Array[(Int32, PlacedDrawingFrame)] = []
  for index, line in self.lines {
    for image in line.drawings {
      if image.anchor is Some(_) {
        result.push((index, image))
      }
    }
  }
  result.sort_by((a, b) => {
    let left = a.1.anchor.unwrap()
    let right = b.1.anchor.unwrap()
    if left.behind != right.behind {
      if left.behind {
        -1
      } else {
        1
      }
    } else if left.order != right.order {
      left.order.compare(right.order)
    } else if a.0 != b.0 {
      a.0.compare(b.0)
    } else {
      a.1.start.compare(b.1.start)
    }
  })
  result
}

///|
fn PlacedDrawingFrame::paint(
  self : PlacedDrawingFrame,
  primitives : Array[PositionedPrimitive],
  fonts : Array[FontInfo],
) -> Unit {
  let math = match self.content {
    Math(formula) => Some(formula.primitives)
    Chart(chart) => Some(chart.primitives)
    _ => None
  }
  if math is Some(math) {
    primitives.push(
      Transform({ a: 1, b: 0, c: 0, d: 1, e: self.x, f: self.y, }),
    )
    primitives.append(math)
    primitives.push(Restore)
    return
  }
  if self.content is (Shape(shape) | TextBox(shape, _)) {
    primitives.push(
      Transform({ a: 1, b: 0, c: 0, d: 1, e: self.x, f: self.y, }),
    )
    primitives.push(
      Path(
        shape.path(self.width, self.height),
        shape.fill,
        shape.stroke,
        shape.lineWidth,
        {
          fillAlpha: 1,
          strokeAlpha: shape.strokeAlpha,
          dash: [],
          cap: if shape.preset == "polyline" {
            1
          } else {
            0
          },
          join: if shape.preset == "polyline" {
            1
          } else {
            0
          },
          miter: 10,
        },
      ),
    )
    if self.content is TextBox(_, text) {
      if text.clip {
        primitives.push(
          Clip({ x: 0, y: 0, width: self.width, height: self.height, }),
        )
      }
      for line in text.lines {
        primitives.append(line.positioned(fonts, self.width))
      }
      if text.clip {
        primitives.push(Restore)
      }
    }
    primitives.push(Restore)
    return
  }
  guard self.content is Picture(key, crop) else { return }
  let width = self.width / (1 - crop[0] - crop[2])
  let height = self.height / (1 - crop[1] - crop[3])
  primitives.push(
    Clip({ x: self.x, y: self.y, width: self.width, height: self.height, }),
  )
  primitives.push(
    Image(
      {
        key,
        x: self.x - crop[0] * width,
        y: self.y - crop[1] * height,
        width,
        height,
      },
      1,
    ),
  )
  primitives.push(Restore)
}

///|
fn Layout::image_hit(
  self : Layout,
  line : Line,
  image : PlacedDrawingFrame,
  page : Int32,
  index : Int32,
  x : Double,
) -> Hit {
  let leading = (x < image.x + image.width / 2) == (image.level % 2 == 0)
  let clip = line.clip && image.anchor is None
  let (_, y, _, height) = image.interaction_bounds()
  let top = if clip { y.max(line.y) } else { y }
  let bottom = if clip {
    (y + height).min(line.y + line.height)
  } else {
    y + height
  }
  self.clip_cell_hit(
    {
      paragraph: line.paragraph,
      offset: image.start + (if leading { 0 } else { 1 }),
      affinity: if leading {
        "after"
      } else {
        "before"
      },
      bidiLevel: Some(image.level),
      frameStart: None,
      drawingStart: Some(image.start),
      page,
      line: index,
      x: if x < image.x + image.width / 2 {
        image.x
      } else {
        image.x + image.width
      },
      y: top,
      height: (bottom - top).max(0),
      reason: line.readOnlyReason,
    },
    line,
  )
}

///|
fn Layout::floating_image_hit(
  self : Layout,
  page : Int32,
  x : Double,
  y : Double,
) -> Hit? raise @failure.Failure {
  let frame = self.pages[page]
  let text = (frame.lines + self.running.get(page).unwrap_or([])).any(line => {
    !line.text.is_empty() &&
    y >= line.y &&
    y <= line.y + line.height &&
    (for index in 1..<line.carets.length() {
      let a = line.carets[index - 1].after
      let b = line.carets[index].before
      if x >= a.min(b) && x <= a.max(b) {
        break true
      }
    } nobreak {
      false
    })
  })
  for (index, image) in frame.floating_images().rev() {
    let (left, top, width, height) = image.interaction_bounds()
    if !(image.anchor.unwrap().behind && text) &&
      x >= left &&
      x <= left + width &&
      y >= top &&
      y <= top + height &&
      image.ink_hit(x, y) {
      return Some(
        self
        .text_box_hit(image, page, x, y)
        .unwrap_or_else(() => {
          self.image_hit(frame.lines[index], image, page, index, x)
        }),
      )
    }
  }
  None
}
