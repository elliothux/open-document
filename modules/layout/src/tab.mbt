///|
priv struct TabLayout {
  interval : Double
  origin : Double
  left : Double
  limit : Double
}

///|
fn TabLayout::advance(self : TabLayout, width : Double) -> Double {
  // shortcut: Stops use the physical left frame; mirror stops with RTL paragraph direction support.
  let x = width + self.origin
  let target = if x < self.left {
    self.left
  } else if self.interval == 0 {
    x
  } else {
    ((x * 20).round() / (self.interval * 20)).floor() * self.interval +
    self.interval
  }
  (target.min(self.limit) - x).max(0)
}

///|
fn LineGroup::tab_run(
  self : LineGroup,
  width : Double,
  x : Double,
  start : Int,
  spans : Array[MeasuredSpan],
) -> PlacedRun {
  let carets = [
    { offset: 0, before: 0, after: 0, },
    { offset: 1, before: width, after: width, },
  ]
  let sources = spans
    .filter(item => item.start <= start && item.end > start)
    .map(item => {
      node: item.span.node,
      start: start - item.start,
      end: start + 1 - item.start,
      offset: 0,
    })
  {
    start,
    sources,
    color: self.style.color,
    size: self.style.render_size(),
    nominalSize: self.style.size,
    text: "\t",
    glyphs: [],
    bidi: [
      {
        start: 0,
        end: 1,
        level: self.level,
        font: self.font,
        script: "Zyyy",
        language: "und",
      },
    ],
    x,
    baseline: 0,
    rise: self.style.rise(),
    decorations: line_decorations(carets, spans, start, width),
  }
}
