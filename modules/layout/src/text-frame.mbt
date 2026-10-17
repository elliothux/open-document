///|
/// Shape one bounded paragraph without document pagination or platform measurement.
/// `baseLevel` fixes the bidi base to 0 (LTR) or 1 (RTL); omitted uses paragraph rules.
pub fn TextProbe::paragraph_lines(
  self : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  width : Double,
  wrap : Bool,
  baseLevel? : Int,
) -> Array[Line] raise @failure.Failure {
  self.check()
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
    if wrap {
      width
    } else {
      1000000000.0
    },
    baseLevel?,
  )
  if self.paragraphs.length() >= 1024 {
    self.paragraphs.clear()
    self.text_units = 0
  }
  for key, items in cache.current {
    if !self.paragraphs.contains(key) {
      let units = paragraph_cache_units(key, items.map(item => item.line))
      if units <= 1048576 - self.text_units {
        self.paragraphs[key] = items
        self.text_units += units
      }
    }
  }
  lines.map(item => item.line.copy_geometry())
}
