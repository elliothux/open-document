///|
enum ParagraphKeySource {
  Version(Int32)
  Content(String)
  Block(UInt64, Array[(Int32, String, TextStyle)])
} derive(Eq, Hash)

///|
pub extend ParagraphKeySource with Eq::{equal, not_equal}

///|
pub extend ParagraphKeySource with Hash::{hash, hash_combine}

///|
struct ParagraphCacheKey {
  source : ParagraphKeySource
  width : UInt64
  profile : String
  startOffset : Int32
  baseLevel : Int32?
  inTable : Bool
  wrap : Bool
  ligatures : Bool
  cell : Bool
  writerTwips : Bool
} derive(Eq, Hash)

///|
pub extend ParagraphCacheKey with Eq::{equal, not_equal}

///|
pub extend ParagraphCacheKey with Hash::{hash, hash_combine}

///|
fn ParagraphCacheKey::units(self : ParagraphCacheKey) -> Int32 {
  // Charge fixed key fields as well as the retained strings.
  32 +
  self.profile.length() +
  (match self.source {
    Version(_) => 0
    Content(content) => content.length()
    Block(_, spans) =>
      spans
      .fold(init=8L, (units, span) => {
        let (_, text, style) = span
        units +
        32L +
        text.length().to_int64() +
        style.font.length().to_int64() +
        style.color.length().to_int64() +
        style.highlight.length().to_int64() +
        style.script.length().to_int64() +
        style.kerning.length().to_int64()
      })
      .min(1048577L)
      .to_int()
  })
}

///|
struct CachedParagraph {
  lines : Array[MeasuredLine]
  units : Int32
}

///|
priv struct ParagraphCache {
  previous : Map[ParagraphCacheKey, CachedParagraph]
  current : Map[ParagraphCacheKey, CachedParagraph]
  profile : String
  versions : ParagraphVersions?
  text_block : Bool
  mut units : Int32
  mut shaped : Int32
  mut reused : Int32
}

///|
fn ParagraphCache::new(
  probe : TextProbe,
  profile : Map[String, String],
  source_versions~ : Bool = false,
  text_block~ : Bool = false,
) -> ParagraphCache {
  let keys = profile.keys().collect()
  keys.sort()
  {
    previous: probe.paragraphs,
    current: Map([]),
    versions: if source_versions {
      Some({ probe, current: Map([]), units: 0, })
    } else {
      None
    },
    text_block,
    profile: Json::array(
      keys.map(key => Json::array([Json(key), Json(profile[key])])),
    ).stringify(),
    units: 0,
    shaped: 0,
    reused: 0,
  }
}

///|
fn paragraph_cache_units(key_units : Int32, lines : Array[Line]) -> Int32 {
  let mut units = key_units
  if units > 1048576 {
    return 1048577
  }
  for line in lines {
    units += 15 +
      (if line.cellClip is Some(_) { 4 } else { 0 }) +
      line.text.length() +
      line.markerText.length() +
      line.readOnlyReason.length() +
      line.carets.length() * 3 +
      line.bars.length()
    for image in line.drawings {
      units += 12 +
        (match image.content {
          Picture(key, _) => key.length()
          Math(formula) => formula.cache_units()
          Chart(chart) => chart.cache_units()
          Metafile(file) => file.cache_units()
          Shape(shape) =>
            shape.preset.length() +
            shape.fill.length() +
            shape.stroke.length() +
            shape.points.length() * 4
          TextBox(shape, text) =>
            shape.preset.length() +
            shape.fill.length() +
            shape.stroke.length() +
            paragraph_cache_units(0, text.lines) +
            text.borders.length() * 7
        })
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
    paragraph.lineGrid.unwrap_or(0),
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
    numbers.push(span.style.spacing)
    if span.drawing is Some(image) {
      numbers.push(image.width)
      numbers.push(image.height)
      let (left, top, right, bottom) = image.effectExtent
      numbers.append([left, top, right, bottom])
      match image.content {
        Math(formula) => numbers.push(formula.style.size)
        Chart(_) => ()
        Metafile(_) => ()
        Picture(_, crop) => numbers.append(crop)
        Shape(shape) => {
          numbers.append([shape.lineWidth, shape.strokeAlpha])
          for point in shape.points {
            numbers.append([point.0, point.1])
          }
        }
        TextBox(shape, text) => {
          numbers.push(shape.lineWidth)
          numbers.append(text.insets)
          if !text.paragraphs.all(p => p.finite_geometry()) {
            return false
          }
        }
      }
    }
  }
  !numbers.any(value => value.is_nan() || value.is_inf())
}

///|
fn ParagraphCache::key(
  self : ParagraphCache,
  paragraph : Paragraph,
  available : Double,
  version : ParagraphVersion?,
  startOffset~ : Int32 = 0,
  baseLevel? : Int32,
  inTable~ : Bool = false,
  wrap~ : Bool = true,
  ligatures~ : Bool = true,
  cell~ : Bool = false,
  writer_twips~ : Bool = true,
) -> ParagraphCacheKey raise @failure.Failure {
  if !self.text_block &&
    !version.map(version => version.checked).unwrap_or(false) {
    for span in paragraph.spans {
      if span.drawing is Some(frame) && frame.content is (Math(_) | Chart(_)) {
        frame.validate()
      }
    }
  }
  let source = if version is Some(version) {
    version.checked = true
    Version(version.number)
  } else if self.text_block {
    Block(
      paragraph.nominalSize.reinterpret_as_uint64(),
      paragraph.spans.map(span => (span.node, span.text, span.style)),
    )
  } else {
    Content(paragraph.to_json().stringify())
  }
  {
    source,
    width: available.reinterpret_as_uint64(),
    profile: self.profile,
    startOffset,
    baseLevel,
    inTable,
    wrap,
    ligatures,
    cell,
    writerTwips: writer_twips,
  }
}

///|
fn ParagraphCache::keep(
  self : ParagraphCache,
  key : ParagraphCacheKey,
  entry : CachedParagraph,
) -> Unit {
  if !self.current.contains(key) && self.current.length() < 1024 {
    let units = entry.units + entry.lines.length()
    if units <= 1048576 - self.units {
      self.current[key] = entry
      self.units += units
    }
  }
}

///|
fn ParagraphCache::retain(
  self : ParagraphCache,
  paragraph : Paragraph,
  available : Double,
  inTable~ : Bool = false,
) -> Unit raise @failure.Failure {
  self.reused += 1
  let key = self.key(paragraph, available, self.version(paragraph), inTable~)
  if self.previous.get(key) is Some(entry) {
    self.keep(key, entry)
  }
}

///|
fn ParagraphCache::lines(
  self : ParagraphCache,
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  available : Double,
  baseLevel? : Int32,
  inTable~ : Bool = false,
  startOffset~ : Int32 = 0,
  wrap~ : Bool = true,
  ligatures~ : Bool = true,
  cell~ : Bool = false,
  writer_twips~ : Bool = true,
) -> Array[MeasuredLine] raise @failure.Failure {
  probe.check()
  // Keep non-finite geometry out of retained entries.
  let version = self.version(paragraph)
  if available.is_nan() ||
    available.is_inf() ||
    (version is None && !paragraph.finite_geometry()) {
    let lines = paragraph_lines(
      probe,
      paragraph,
      profile,
      available,
      baseLevel?,
      inTable~,
      startOffset~,
      wrap~,
      ligatures~,
      cell~,
      writer_twips~,
    )
    self.shaped += 1
    return lines
  }
  let key = self.key(
    paragraph,
    available,
    version,
    startOffset~,
    baseLevel?,
    inTable~,
    wrap~,
    ligatures~,
    cell~,
    writer_twips~,
  )
  if self.current.get(key) is Some(entry) {
    self.reused += 1
    return entry.lines
  }
  if self.previous.get(key) is Some(entry) {
    self.reused += 1
    if !self.text_block {
      self.keep(key, entry)
    }
    return entry.lines
  }
  let lines = paragraph_lines(
    probe,
    paragraph,
    profile,
    available,
    baseLevel?,
    inTable~,
    startOffset~,
    wrap~,
    ligatures~,
    cell~,
    writer_twips~,
  )
  self.shaped += 1
  if self.current.length() < 1024 {
    let units = paragraph_cache_units(key.units(), lines.map(item => item.line))
    self.keep(key, { lines, units, })
  }
  lines
}

///|
fn TextProbe::retain_text_cache(
  self : TextProbe,
  cache : ParagraphCache,
) -> Unit {
  guard !cache.current.is_empty() else { return }
  if self.paragraphs.length() >= 1024 {
    self.paragraphs.clear()
    self.text_units = 0
  }
  for key, entry in cache.current {
    if !self.paragraphs.contains(key) &&
      entry.units <= 1048576 - self.text_units {
      self.paragraphs[key] = entry
      self.text_units += entry.units
    }
  }
}
