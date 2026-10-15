///|
fn WordTree::number_level(
  self : WordTree,
  level : Int,
) -> (Int, NumberLevel) raise @failure.Failure {
  self.numbering_shape(level, ["ilvl", "tplc", "tentative"], [
    "start", "numFmt", "lvlRestart", "lvlText", "lvlJc", "suff", "pPr", "rPr",
  ])
  let index = numbering_integer(
    self.nodes[level].attribute("ilvl", uri=word_uri).unwrap_or("-1"),
    8,
  )
  guard self.numbering_value(level, "numFmt") is Some(format) &&
    [
      "decimal", "decimalZero", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman",
      "bullet",
    ].contains(format) &&
    self.numbering_value(level, "lvlText") is Some(pattern) &&
    !pattern.is_empty() &&
    !pattern
    .iter()
    .any(ch => ch < ' ' || ch == '\u007f' || ch == '\u2028' || ch == '\u2029') &&
    pattern.length() <= 256 else {
    @failure.reject("unsupported-numbering", "Unsupported numbering level")
  }
  let align = self.numbering_value(level, "lvlJc").unwrap_or("left")
  let suffix = self.numbering_value(level, "suff").unwrap_or("tab")
  guard ["left", "right", "center"].contains(align) &&
    ["tab", "space", "nothing"].contains(suffix) else {
    @failure.reject(
      "unsupported-numbering", "Unsupported numbering alignment or suffix",
    )
  }
  if self.child(level, "pPr") is Some(p) {
    self.check_structure_properties(p)
  }
  if self.child(level, "rPr") is Some(p) {
    self.check_structure_properties(p)
    guard self.child(p, "rStyle") is None else {
      @failure.reject(
        "unsupported-numbering", "Numbering character style references are unsupported",
      )
    }
  }
  (
    index,
    {
      node: level,
      start: self
      .numbering_value(level, "start")
      .map(v => numbering_integer(v, 2147483646))
      .unwrap_or(0),
      restart: self
      .numbering_value(level, "lvlRestart")
      .map(v => numbering_integer(v, index))
      .unwrap_or(-1),
      format,
      pattern,
      align,
      suffix,
    },
  )
}
