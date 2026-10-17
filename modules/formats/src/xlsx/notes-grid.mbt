///|
fn note_marker(
  rect : @layout.Border,
  rtl : Bool,
) -> @layout.PositionedPrimitive {
  let size = 4.5.min(rect.width).min(rect.height)
  let x = if rtl {
    rect.x + 0.75.min(rect.width)
  } else {
    rect.x + rect.width - 0.75.min(rect.width)
  }
  let end = x + (if rtl { size } else { -size })
  Path(
    [
      @layout.PathSegment::Move(end, rect.y),
      Line(x, rect.y),
      Line(x, rect.y + size),
      Close,
    ],
    "ff9000",
    "",
    0,
    { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 10, },
  )
}
