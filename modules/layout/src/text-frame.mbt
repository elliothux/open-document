///|
/// Shape one bounded paragraph without document pagination or platform measurement.
/// `baseLevel` fixes the bidi base to 0 (LTR) or 1 (RTL); omitted uses paragraph rules.
/// `ligatures=false` disables optional ligatures while preserving required script shaping.
pub fn TextProbe::paragraph_lines(
  self : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  width : Double,
  wrap : Bool,
  baseLevel? : Int32,
  ligatures~ : Bool = true,
) -> Array[Line] raise @failure.Failure {
  self.check()
  guard paragraph.spans.all(span => {
    span.drawing.bind(image => image.anchor) is None
  }) else {
    @failure.reject(
      "unsupported-layout", "Floating images require document pagination",
    )
  }
  guard baseLevel is (None | Some(0 | 1)) else {
    @failure.reject("invalid-style", "Bidi base level must be 0 or 1")
  }
  guard width > 0 && width <= 14400 else {
    @failure.reject("layout-overflow", "Text frame has no usable line width")
  }
  let cache = ParagraphCache::new(self, profile)
  let lines = cache.lines(
    self,
    paragraph,
    profile,
    width,
    baseLevel?,
    wrap~,
    ligatures~,
    writer_twips=false,
  )
  self.retain_text_cache(cache)
  lines.map(item => item.line.copy_geometry())
}

///|
fn paragraph_lines(
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
  let source = prepare_paragraph(
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
  let lines = []
  let mut start = startOffset
  while start < source.text.length() ||
        (source.text.is_empty() && lines.is_empty()) {
    let measured = (source.line)(start, 0, available)
    lines.push(measured)
    start = measured.line.end
  }
  if source.text.has_suffix("\n") ||
    source.text.has_suffix("\u000b") ||
    source.text.has_suffix("\u000c") {
    lines.push((source.line)(start, 0, available))
  }
  validate_paragraph_leaders(lines)
  lines
}

///|
fn validate_paragraph_leaders(
  lines : Array[MeasuredLine],
) -> Unit raise @failure.Failure {
  let count = lines.fold(init=0, (sum, item) => {
    sum +
    item.line.runs
    .iter()
    .filter(run => run.text == "\t")
    .fold(init=0, (sum, run) => sum + run.glyphs.length())
  })
  guard count <= 65536 else {
    @failure.reject("limit-exceeded", "Paragraph leader glyph budget exceeded")
  }
}
