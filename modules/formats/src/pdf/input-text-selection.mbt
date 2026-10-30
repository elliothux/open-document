///|
fn crop_intersects(page : SourcePage, points : Array[Double]) -> Bool {
  guard points.length() >= 4 else { return false }
  let mut left = points[0]
  let mut right = points[0]
  let mut top = points[1]
  let mut bottom = points[1]
  for i = 2; i < points.length(); i = i + 2 {
    left = left.min(points[i])
    right = right.max(points[i])
    top = top.min(points[i + 1])
    bottom = bottom.max(points[i + 1])
  }
  if left == right || top == bottom {
    // Spaces have an advance segment on the baseline, with no ink area.
    return right >= 0 && bottom >= 0 && left <= page.width && top <= page.height
  }
  right > 0 && bottom > 0 && left < page.width && top < page.height
}

///|
fn glyph_ink_quad(
  probe : @layout.TextProbe,
  font : Int32,
  glyph : UInt32,
  transform : @layout.Matrix,
  x : Double,
  y : Double,
) -> Array[Double] raise @failure.Failure {
  let bounds = probe.source_glyph_bounds(font, glyph)
  let upem = probe.font_info()[font].upem.to_double()
  if bounds is [a, b, c, d] {
    extraction_quad(
      transform.then({
        a: (c - a) / upem,
        b: 0,
        c: 0,
        d: (d - b) / upem,
        e: x + a / upem,
        f: y - d / upem,
      }),
    )
  } else {
    []
  }
}

///|
fn selected_spans(
  display : PageDisplay,
  start : Int32,
  end : Int32,
) -> Array[TextSpan] {
  display.spans.filter(span => {
    span.cropVisible && span.start < end && span.end > start
  })
}

///|
fn crop_visible_ranges(display : PageDisplay) -> Set[(Int32, Int32)] {
  // ActualText shares one semantic range across several physical glyphs.
  // Keep that replacement when any of its glyphs intersects the page crop.
  let visible = Set([])
  for span in display.spans {
    if span.cropVisible {
      visible.add((span.start, span.end))
    }
  }
  visible
}

///|
fn visible_text(
  display : PageDisplay,
  start : Int32,
  end : Int32,
) -> String raise @failure.Failure {
  let visible = crop_visible_ranges(display)
  if !display.spans.any(span => {
      !visible.contains((span.start, span.end)) &&
      span.start < end &&
      span.end > start
    }) {
    guard !display.spans.any(span => {
      !span.mapped && span.start < end && span.end > start
    }) else {
      @failure.reject("unmapped-text", "PDF selection contains unknown Unicode")
    }
    return display.text[start:end].to_owned()
  }
  let output = StringBuilder()
  let gap : Array[String] = []
  let mut previous = start
  let mut written = false
  for span in display.spans {
    if span.end <= start || span.start >= end {
      continue
    }
    let low = span.start.max(start)
    let high = span.end.min(end)
    if low > previous {
      // Only generated separators are gaps; hidden source glyphs are skipped.
      gap.push(display.text[previous:low].to_owned())
    }
    if visible.contains((span.start, span.end)) && high > previous {
      guard span.mapped else {
        @failure.reject(
          "unmapped-text", "PDF selection contains unknown Unicode",
        )
      }
      if written {
        output.write_string(gap.join(""))
      }
      gap.clear()
      output.write_string(display.text[low.max(previous):high].to_owned())
      written = true
    }
    previous = previous.max(high)
  }
  output.to_string()
}
