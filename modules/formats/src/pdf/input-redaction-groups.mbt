///|
/// Preserve source text-show semantics independently of the font's nominal
/// widths. Source PDFs may deliberately use different PDF advance metrics.
fn redaction_text_groups(
  page : Int32,
  glyphs : Array[PdfExtractedGlyph],
  removed : Map[Int32, Bool],
  primitives : Array[@layout.PositionedPrimitive],
) -> Array[PdfTextGroup] raise @failure.Failure {
  let kept = glyphs.filter(glyph => !removed.contains(glyph.group))
  let indices : Map[Int32, Int32] = Map([])
  let groups : Array[PdfTextGroup] = []
  let texts : Array[StringBuilder] = []
  let mut record = 0
  for index, primitive in primitives {
    if primitive is Text(_) {
      guard record < kept.length() &&
        index >= 2 &&
        index + 2 < primitives.length() &&
        primitives[index - 2] is Transform(_) &&
        primitives[index - 1] is Transform(_) &&
        primitives[index + 1] is Restore &&
        primitives[index + 2] is Restore else {
        @failure.reject(
          "protected-content", "Clean text has no balanced source glyph scope",
        )
      }
      let glyph = kept[record]
      if indices.get(glyph.group) is Some(group) {
        let previous = groups[group]
        groups[group] = { ..previous, end: index + 3, }
        texts[group].write_string(glyph.text)
      } else {
        indices[glyph.group] = groups.length()
        let text = StringBuilder()
        text.write_string(glyph.text)
        texts.push(text)
        groups.push({ page, start: index - 2, end: index + 3, text: "", })
      }
      record += 1
    }
  }
  guard record == kept.length() else {
    @failure.reject(
      "protected-content", "Clean text and source glyph records disagree",
    )
  }
  let mut end = 0
  for index, group in groups {
    guard group.start >= end else {
      @failure.reject("protected-content", "Clean semantic text groups overlap")
    }
    end = group.end
    groups[index] = { ..group, text: texts[index].to_string(), }
  }
  groups
}
