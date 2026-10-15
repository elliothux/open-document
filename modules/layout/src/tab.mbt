///|
pub(all) struct TabStop {
  position : Double
  align : String
  leader : String
} derive(Eq, ToJson)

///|
pub extend TabStop with Eq::{equal, not_equal}

///|
pub extend TabStop with ToJson::{to_json}

///|
pub fn validate_tabs(stops : Array[TabStop]) -> Unit raise @failure.Failure {
  guard stops.length() <= 64 else {
    @failure.reject("limit-exceeded", "Too many tab stops")
  }
  let mut previous = -1.0
  for stop in stops {
    guard stop.position >= 0 &&
      stop.position <= 1584 &&
      stop.position * 20 == (stop.position * 20).to_int().to_double() &&
      stop.position > previous &&
      ["left", "right", "center", "decimal", "bar"].contains(stop.align) &&
      ["none", "dot", "hyphen", "underscore", "heavy", "middleDot"].contains(
        stop.leader,
      ) &&
      (stop.align != "bar" || stop.leader == "none") else {
      @failure.reject(
        "invalid-operation", "Tab stops must be ordered, unique and use integer twips within 1584 points",
      )
    }
    previous = stop.position
  }
}

///|
priv struct TabLayout {
  interval : Double
  origin : Double
  left : Double
  limit : Double
  stops : Array[TabStop]
  decimalSymbol : String
}

///|
fn TabLayout::next(self : TabLayout, width : Double) -> TabStop {
  // shortcut: Stops use the physical left frame; mirror stops with RTL paragraph direction support.
  let x = width + self.origin
  for stop in self.stops {
    if stop.align != "bar" &&
      (stop.position * 20).round() > (x * 20).round() &&
      !(x < self.left && stop.position > self.left) {
      return stop
    }
  }
  let target = if x < self.left {
    self.left
  } else if self.interval == 0 {
    x
  } else {
    ((x * 20).round() / (self.interval * 20)).floor() * self.interval +
    self.interval
  }
  { position: target, align: "left", leader: "none", }
}

///|
fn TabLayout::advance(
  self : TabLayout,
  width : Double,
  following~ : Double = 0,
  decimal~ : Double = 0,
) -> Double {
  let stop = self.next(width)
  let shift = if stop.position > self.limit && self.stops.contains(stop) {
    following
  } else {
    match stop.align {
      "right" => following
      "center" => following / 2
      "decimal" => decimal
      _ => 0.0
    }
  }
  (stop.position.min(self.limit) - shift - width - self.origin).max(0)
}

///|
fn TabLayout::needs_following(self : TabLayout, width : Double) -> Bool {
  let stop = self.next(width)
  stop.align != "left" ||
  (stop.position > self.limit && self.stops.contains(stop))
}

///|
fn tab_segment_end(text : String, start : Int) -> Int {
  for i in start..<text.length() {
    if text[i] == 9 || text[i] == 10 || text[i] == 12 {
      return i
    }
  }
  text.length()
}

///|
fn tab_decimal(text : String, start : Int, end : Int, symbol : String) -> Int {
  for i in start..<end {
    if i + symbol.length() <= end &&
      text[i:i + symbol.length()].to_owned() == symbol {
      return i
    }
  }
  end
}

///|
fn TabLayout::estimated_advance(
  self : TabLayout,
  width : Double,
  text : String,
  offset : Int,
  advances : Array[(Double, Double)],
) -> Double {
  if !self.needs_following(width) {
    return self.advance(width)
  }
  let end = tab_segment_end(text, offset + 1)
  let point = tab_decimal(text, offset + 1, end, self.decimalSymbol)
  let mut following = 0.0
  let mut decimal = 0.0
  for i in (offset + 1)..<end {
    let advance = advances[i].0 +
      (if i > offset + 1 { advances[i].1 } else { 0.0 })
    following += advance
    if i < point {
      decimal += advance
    }
  }
  self.advance(width, following~, decimal~)
}

///|
fn LineGroup::tab_run(
  self : LineGroup,
  probe : TextProbe,
  width : Double,
  x : Double,
  start : Int,
  spans : Array[MeasuredSpan],
  leader : String,
) -> PlacedRun raise @failure.Failure {
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
  let glyphs = probe.tab_leader(
    leader,
    self.font,
    self.style.render_size(),
    width,
  )
  {
    start,
    sources,
    color: self.style.color,
    size: self.style.render_size(),
    nominalSize: self.style.size,
    text: "\t",
    glyphs,
    bidi: [
      {
        start: 0,
        end: 1,
        level: self.level,
        font: glyphs.get(0).map(glyph => glyph.font).unwrap_or(self.font),
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
