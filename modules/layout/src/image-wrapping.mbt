///|
priv struct WrappingRect {
  page : Int
  paragraph : Int
  start : Int
  left : Double
  top : Double
  right : Double
  bottom : Double
  wrapping : String
  side : String
} derive(ToJson)

///|
fn wrapping_rects(
  pages : Array[PageFrame],
  columns : Int,
) -> Array[WrappingRect] {
  let result = []
  for page, frame in pages {
    for line in frame.lines {
      for image in line.images {
        if image.anchor is Some(anchor) && anchor.wrapping != "none" {
          result.push({
            page: page / columns,
            paragraph: line.paragraph,
            start: image.start,
            left: image.x - anchor.distance.left,
            top: image.y - anchor.distance.top,
            right: image.x + image.width + anchor.distance.right,
            bottom: image.y + image.height + anchor.distance.bottom,
            wrapping: anchor.wrapping,
            side: anchor.wrapSide,
          })
        }
      }
    }
  }
  result.sort_by((a, b) => {
    if a.page != b.page {
      a.page.compare(b.page)
    } else if a.paragraph != b.paragraph {
      a.paragraph.compare(b.paragraph)
    } else {
      a.start.compare(b.start)
    }
  })
  result
}

///|
fn Pagination::wrapping_floor(
  self : Pagination,
  page : Int,
  y : Double,
  height : Double,
  square~ : Bool = true,
) -> Double {
  let frame = self.page_at(page)
  let mut result = y
  for _ in 0..<=self.wrapping.length() {
    let before = result
    for rect in self.wrapping {
      if (square || rect.wrapping != "square") &&
        rect.page == page / self.columns.count &&
        rect.left <= frame.width - frame.right &&
        rect.right >= frame.left &&
        result + height > rect.top + 0.0000001 &&
        result < rect.bottom - 0.0000001 {
        result = rect.bottom
      }
    }
    if result == before {
      break
    }
  }
  result
}

///|
fn Pagination::avoid_wrapping(
  self : Pagination,
  height : Double,
  square~ : Bool = true,
) -> Unit {
  self.y = self.wrapping_floor(self.pages.length() - 1, self.y, height, square~)
}

///|
fn Pagination::detach_wrapping_images(
  self : Pagination,
  line : Line,
  images : Images,
) -> Line raise @failure.Failure {
  let wrapped = line.images.filter(image => {
    image.anchor is Some(anchor) && anchor.wrapping != "none"
  })
  if wrapped.is_empty() {
    return line
  }
  for image in wrapped {
    let identity = (line.paragraph, image.start)
    if self.placedWrapping.contains(identity) {
      continue
    }
    // The source anchor stays on its page when exclusion pushes its following text onward.
    self.place(
      {
        ..line,
        text: "",
        start: image.start,
        end: image.start + 1,
        width: 0,
        caretOnly: true,
        runs: [],
        marker: [],
        markerText: "",
        bars: [],
        images: [image],
        carets: [
          { offset: image.start, before: image.x, after: image.x, },
          { offset: image.start + 1, before: image.x, after: image.x, },
        ],
      },
      self.page.left,
      self.y,
      images,
    )
    self.placedWrapping[identity] = ()
    let placed = self.pages.last().unwrap().lines.last().unwrap().images[0]
    let anchor = placed.anchor.unwrap()
    let rect : WrappingRect = {
      page: (self.pages.length() - 1) / self.columns.count,
      paragraph: line.paragraph,
      start: image.start,
      left: placed.x - anchor.distance.left,
      top: placed.y - anchor.distance.top,
      right: placed.x + placed.width + anchor.distance.right,
      bottom: placed.y + placed.height + anchor.distance.bottom,
      wrapping: anchor.wrapping,
      side: anchor.wrapSide,
    }
    let old = for index, value in self.wrapping {
      if value.paragraph == rect.paragraph && value.start == rect.start {
        break Some(index)
      }
    } nobreak {
      None
    }
    if old is Some(index) {
      self.wrapping[index] = rect
    } else {
      self.wrapping.push(rect)
    }
  }
  {
    ..line,
    images: line.images.filter(image => {
      image.anchor is None || image.anchor.unwrap().wrapping == "none"
    }),
  }
}
