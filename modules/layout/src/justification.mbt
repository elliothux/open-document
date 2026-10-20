///|
priv struct Justification {
  trailing : (Double, Double)
  stops : Array[Double]
  extra : Double
}

///|
fn Justification::trim(self : Justification, x : Double) -> Double {
  x - (x - self.trailing.0).clamp(min=0, max=self.trailing.1 - self.trailing.0)
}

///|
fn Justification::position(self : Justification, x : Double) -> Double {
  let x = self.trim(x)
  let count = for left = 0, right = self.stops.length(); left < right; {
    let middle = left + (right - left) / 2
    if self.stops[middle] <= x + 0.000001 {
      continue middle + 1, right
    }
    continue left, middle
  } nobreak {
    left
  }
  x +
  (self.extra * 20 * count.to_double() / self.stops.length().to_double()).round() /
  20
}

///|
fn justify_space(text : String, start : Int, end : Int) -> Bool {
  end == start + 1 && (text[start] == 32 || text[start] == 0x3000)
}

///|
// Expand after shaping so GDEF carets and contextual glyphs stay intact.
fn justified_line(line : Line, limit : Double) -> Line {
  let text = line.text
  let carets = line.carets
  if carets.length() < 3 {
    return line
  }
  let mut first = 0
  let mut last = carets.length() - 1
  while first < last &&
        justify_space(
          text,
          carets[first].offset - line.start,
          carets[first + 1].offset - line.start,
        ) {
    first += 1
  }
  while last > first &&
        justify_space(
          text,
          carets[last - 1].offset - line.start,
          carets[last].offset - line.start,
        ) {
    last -= 1
  }
  if first == last {
    return line
  }
  let trailing = if last == carets.length() - 1 {
    (0.0, 0.0)
  } else {
    let positions = carets[last:carets.length() - 1].mapi((i, a) => {
      let b = carets[last + i + 1]
      (a.after.min(b.before), a.after.max(b.before))
    })
    (
      positions.iter().fold(init=line.width, (x, range) => x.min(range.0)),
      positions.iter().fold(init=0, (x, range) => x.max(range.1)),
    )
  }
  let mut plan = { trailing, stops: [], extra: 0, }
  let width = plan.trim(line.width)
  let mut begin = first
  for i in first..<last {
    if text[carets[i].offset - line.start] == 9 {
      begin = i + 1
    }
  }
  while begin < last &&
        justify_space(
          text,
          carets[begin].offset - line.start,
          carets[begin + 1].offset - line.start,
        ) {
    begin += 1
  }
  for i in begin..<last {
    let a = carets[i]
    let b = carets[i + 1]
    if justify_space(text, a.offset - line.start, b.offset - line.start) &&
      b.before != a.after {
      plan.stops.push(plan.trim(a.after.max(b.before)))
    }
  }
  if plan.stops.is_empty() && line.baseLevel % 2 == 0 {
    let clusters : Map[Int, Bool] = Map([])
    for run in line.runs {
      for glyph in run.glyphs {
        clusters[run.start + run.logical_cluster(glyph)] = true
      }
    }
    let close_word = limit - width <= 0.05 * limit
    let legal : Map[Int, Bool] = Map([])
    for (offset, _) in @linebreak.linebreaks(text) {
      legal[offset] = true
    }
    for i in (begin + 1)..<last {
      let boundary = carets[i]
      let left = text[carets[i - 1].offset - line.start:boundary.offset -
        line.start]
        .iter()
        .next()
        .unwrap()
      let right = text[boundary.offset - line.start:].iter().next().unwrap()
      let cjk = character_font_class(left.to_uint(), 0) == 1 ||
        character_font_class(right.to_uint(), 0) == 1
      let letters = letter_numeric_at(text, boundary.offset - line.start - 1) &&
        letter_numeric_at(text, boundary.offset - line.start)
      if clusters.contains(boundary.offset) &&
        (
          (close_word && letters) ||
          (cjk && legal.contains(boundary.offset - line.start))
        ) &&
        (boundary.before - boundary.after).abs() < 0.1 {
        plan.stops.push(plan.trim(boundary.before))
      }
    }
  }
  if plan.stops.is_empty() || width >= limit {
    return line
  }
  plan.stops.sort()
  plan = { ..plan, extra: ((limit - width) * 20).floor() / 20, }
  {
    ..line,
    width: width + plan.extra,
    justified: true,
    carets: carets.map(caret => {
      ..caret,
      before: plan.position(caret.before),
      after: plan.position(caret.after),
    }),
    images: line.images.map(image => { ..image, x: plan.position(image.x), }),
    runs: line.runs.map(run => {
      let x = plan.position(run.x)
      {
        ..run,
        x,
        glyphs: run.glyphs.map(glyph => {
          let origin = run.x + glyph.x - glyph.xOffset.to_double() * glyph.scale
          {
            ..glyph,
            x: plan.position(origin) +
            glyph.xOffset.to_double() * glyph.scale -
            x,
          }
        }),
        decorations: run.decorations.map(decoration => {
          let left = plan.position(run.x + decoration.x)
          let right = plan.position(run.x + decoration.x + decoration.width)
          { ..decoration, x: left - x, width: right - left, }
        }),
      }
    }),
  }
}
