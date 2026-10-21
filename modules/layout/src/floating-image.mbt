///|
pub(all) enum ImageAxis {
  Offset(String, Double)
  Aligned(String, String)
}

///|
pub impl ToJson for ImageAxis with fn to_json(self) {
  match self {
    Offset(reference, value) =>
      { "relativeTo": reference, "offset": value, "align": Json::null() }
    Aligned(reference, value) =>
      { "relativeTo": reference, "offset": Json::null(), "align": value }
  }
}

///|
pub extend ImageAxis with ToJson::{to_json}

///|
pub(all) struct ImageAnchor {
  horizontal : ImageAxis
  vertical : ImageAxis
  behind : Bool
  order : Int64
} derive(ToJson)

///|
pub extend ImageAnchor with ToJson::{to_json}

///|
fn ImageAxis::validate(
  self : ImageAxis,
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
pub fn ImageAnchor::validate(self : ImageAnchor) -> Unit raise @failure.Failure {
  self.horizontal.validate(true)
  self.vertical.validate(false)
  guard self.order >= 0 && self.order <= 4294967295L else {
    @failure.reject("invalid-image", "Invalid floating image layer order")
  }
}

///|
fn ImageAxis::position(
  self : ImageAxis,
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
      if span.image is Some(image) && image.anchor is Some(anchor) {
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
      span.image.bind(image => image.anchor) is Some(_)
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
) -> Array[(Int, PlacedImageFrame)] {
  let result : Array[(Int, PlacedImageFrame)] = []
  for index, line in self.lines {
    for image in line.images {
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
fn PlacedImageFrame::paint(
  self : PlacedImageFrame,
  primitives : Array[PositionedPrimitive],
) -> Unit {
  let width = self.width / (1 - self.crop[0] - self.crop[2])
  let height = self.height / (1 - self.crop[1] - self.crop[3])
  primitives.push(
    Clip({ x: self.x, y: self.y, width: self.width, height: self.height, }),
  )
  primitives.push(
    Image(
      {
        key: self.key,
        x: self.x - self.crop[0] * width,
        y: self.y - self.crop[1] * height,
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
  image : PlacedImageFrame,
  page : Int,
  index : Int,
  x : Double,
) -> Hit {
  let leading = (x < image.x + image.width / 2) == (image.level % 2 == 0)
  let clip = line.clip && image.anchor is None
  let top = if clip { image.y.max(line.y) } else { image.y }
  let bottom = if clip {
    (image.y + image.height).min(line.y + line.height)
  } else {
    image.y + image.height
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
      imageStart: Some(image.start),
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
  page : Int,
  x : Double,
  y : Double,
) -> Hit? {
  let frame = self.pages[page]
  let text = (frame.lines + self.running.get(page).unwrap_or([])).any(line => {
    !line.text.is_empty() &&
    x >= line.x &&
    x <= line.x + line.width &&
    y >= line.y &&
    y <= line.y + line.height
  })
  for (index, image) in frame.floating_images().rev() {
    if !(image.anchor.unwrap().behind && text) &&
      x >= image.x &&
      x <= image.x + image.width &&
      y >= image.y &&
      y <= image.y + image.height {
      return Some(self.image_hit(frame.lines[index], image, page, index, x))
    }
  }
  None
}
