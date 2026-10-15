///|
priv struct ParagraphCache {
  previous : Map[String, Array[MeasuredLine]]
  current : Map[String, Array[MeasuredLine]]
  profile : String
  mut units : Int
  mut shaped : Int
  mut reused : Int
}

///|
fn ParagraphCache::new(
  probe : TextProbe,
  profile : Map[String, String],
) -> ParagraphCache {
  let keys = profile.keys().collect()
  keys.sort()
  {
    previous: probe.paragraphs,
    current: Map([]),
    profile: Json::array(
      keys.map(key => Json::array([Json(key), Json(profile[key])])),
    ).stringify(),
    units: 0,
    shaped: 0,
    reused: 0,
  }
}

///|
fn paragraph_cache_units(key : String, lines : Array[Line]) -> Int {
  let mut units = key.length()
  if units > 1048576 {
    return 1048577
  }
  for line in lines {
    units += 13 +
      line.text.length() +
      line.markerText.length() +
      line.readOnlyReason.length() +
      line.carets.length() * 3 +
      line.bars.length()
    for image in line.images {
      units += 4 + image.key.length()
    }
    for run in line.paint_runs() {
      units += 5 +
        run.text.length() +
        run.color.length() +
        run.sources.length() * 4
      for decoration in run.decorations {
        units += 4 + decoration.highlight.length()
      }
      for glyph in run.glyphs {
        units += 10 + glyph.outline.length()
      }
      for bidi in run.bidi {
        units += 4 + bidi.script.length() + bidi.language.length()
      }
    }
    if units > 1048576 {
      return 1048577
    }
  }
  units
}

///|
fn Paragraph::finite_geometry(paragraph : Paragraph) -> Bool {
  let numbers = [
    paragraph.nominalSize,
    paragraph.defaultTab,
    paragraph.before,
    paragraph.after,
    paragraph.left,
    paragraph.right,
    paragraph.first,
    match paragraph.line {
      Auto(value) | Exact(value) | AtLeast(value) => value
    },
  ]
  for stop in paragraph.tabs {
    numbers.push(stop.position)
  }
  if paragraph.marker is Some(marker) {
    numbers.push(marker.style.size)
  }
  for span in paragraph.spans {
    numbers.push(span.style.size)
    if span.image is Some(image) {
      numbers.push(image.width)
      numbers.push(image.height)
    }
  }
  !numbers.any(value => value.is_nan() || value.is_inf())
}

///|
fn ParagraphCache::key(
  self : ParagraphCache,
  paragraph : Paragraph,
  available : Double,
) -> String {
  Json::array([paragraph.to_json(), Json(available), Json(self.profile)]).stringify()
}

///|
fn ParagraphCache::keep(
  self : ParagraphCache,
  key : String,
  lines : Array[MeasuredLine],
) -> Unit {
  if !self.current.contains(key) && self.current.length() < 1024 {
    let units = paragraph_cache_units(key, lines.map(item => item.line)) +
      lines.length()
    if units <= 1048576 - self.units {
      self.current[key] = lines
      self.units += units
    }
  }
}

///|
fn ParagraphCache::retain(
  self : ParagraphCache,
  paragraph : Paragraph,
  available : Double,
) -> Unit {
  self.reused += 1
  let key = self.key(paragraph, available)
  if self.previous.get(key) is Some(lines) {
    self.keep(key, lines)
  }
}

///|
fn ParagraphCache::lines(
  self : ParagraphCache,
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  available : Double,
) -> Array[MeasuredLine] raise @failure.Failure {
  probe.check()
  // Keep non-finite geometry out of retained entries.
  if available.is_nan() || available.is_inf() || !paragraph.finite_geometry() {
    let lines = paragraph_lines(probe, paragraph, profile, available)
    self.shaped += 1
    return lines
  }
  let key = self.key(paragraph, available)
  let cached = match self.current.get(key) {
    Some(lines) => Some(lines)
    None => self.previous.get(key)
  }
  let lines = match cached {
    Some(lines) => {
      self.reused += 1
      lines
    }
    None => {
      let lines = paragraph_lines(probe, paragraph, profile, available)
      self.shaped += 1
      lines
    }
  }
  self.keep(key, lines)
  lines
}
