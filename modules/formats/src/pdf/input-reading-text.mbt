///|
priv struct Token {
  text : String
  font : String
  identity : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
  x : Double
  y : Double
  right : Double
  bottom : Double
  baseline : Double
  angle : Double
}

///|
fn tokens(
  extraction : PdfExtraction,
  families : Map[String, String],
  warnings : Array[String],
  page : Int32,
) -> Array[Token] raise @failure.Failure {
  let result : Array[Token] = []
  let marked : Map[Int32, Bool] = Map([])
  let infos = extraction.probe.font_info()
  let styles = Array::makei(infos.length(), index => {
    extraction.probe.font_style(index)
  })
  guard extraction.glyphs.length() <= 262144 else {
    @failure.reject("limit-exceeded", "PDF conversion exceeds its glyph budget")
  }
  let quads : Map[Int32, Array[Double]] = Map([])
  let firsts : Map[Int32, PdfExtractedGlyph] = Map([])
  let mixed : Map[Int32, Bool] = Map([])
  for glyph in extraction.glyphs {
    if glyph.marked {
      quads.get_or_init(glyph.group, () => []).append(glyph.quad)
      if firsts.get(glyph.group) is Some(first) {
        if first.fontIndex != glyph.fontIndex ||
          (first.size - glyph.size).abs() > 0.1 ||
          first.color != glyph.color {
          mixed[glyph.group] = true
        }
      } else {
        firsts[glyph.group] = glyph
      }
    }
  }
  for glyph in extraction.glyphs {
    if glyph.invisible {
      read_warning(warnings, "Page \{page}: invisible text was omitted")
      continue
    }
    if glyph.clipped {
      read_warning(
        warnings,
        "Page \{page}: clipped text could not be reconstructed and was omitted",
      )
      continue
    }
    if glyph.annotation {
      read_warning(
        warnings,
        "Page \{page}: field and annotation appearances were flattened to editable content",
      )
    }
    guard glyph.mapped else {
      @failure.reject(
        "conversion-unavailable",
        "Page \{page}: Unicode mapping is incomplete",
      )
    }
    guard glyph.fontIndex >= 0 && glyph.fontIndex < infos.length() else {
      @failure.reject(
        "conversion-unavailable",
        "Page \{page}: a source font is unavailable",
      )
    }
    let mut quad = glyph.quad
    if glyph.marked {
      if marked.contains(glyph.group) {
        continue
      }
      marked[glyph.group] = true
      quad = quads[glyph.group]
      if mixed.contains(glyph.group) {
        read_warning(
          warnings,
          "Page \{page}: mixed styling within an ActualText group was flattened",
        )
      }
    }
    if glyph.text.is_empty() {
      continue
    }
    let matrix = glyph.transform
    let xScale = (matrix.a * matrix.a + matrix.b * matrix.b).sqrt()
    let yScale = (matrix.c * matrix.c + matrix.d * matrix.d).sqrt()
    if xScale == 0 ||
      yScale == 0 ||
      (matrix.a * matrix.c + matrix.b * matrix.d).abs() >
      xScale * yScale * 0.001 {
      read_warning(warnings, "Page \{page}: skewed text was omitted")
      continue
    }
    let angle = @math.atan2(matrix.b, matrix.a)
    let cos = @math.cos(angle)
    let sin = @math.sin(angle)
    let projected : Array[Double] = []
    for index in 0..<(quad.length() / 2) {
      projected.append([
        cos * quad[index * 2] + sin * quad[index * 2 + 1],
        -sin * quad[index * 2] + cos * quad[index * 2 + 1],
      ])
    }
    let (x, y, right, bottom) = read_bounds(projected)
    let identity = infos[glyph.fontIndex].identity
    let font = families.get(identity).unwrap_or(glyph.font)
    let lower = glyph.font.to_lower() + " " + font.to_lower()
    if glyph.substituted {
      read_warning(warnings, "Page \{page}: a substituted source font was used")
    }
    result.push({
      text: glyph.text,
      font,
      identity,
      size: glyph.size,
      color: glyph.color,
      bold: styles[glyph.fontIndex].0 ||
      lower.contains("bold") ||
      lower.contains("black"),
      italic: styles[glyph.fontIndex].1 ||
      lower.contains("italic") ||
      lower.contains("oblique") ||
      infos[glyph.fontIndex].italicAngle != 0,
      x,
      y,
      right,
      bottom,
      baseline: -sin * glyph.baseline[0] + cos * glyph.baseline[1],
      angle,
    })
  }
  result
}

///|
fn finish_line(parts : Array[Token]) -> PdfReadLine {
  let runs : Array[PdfReadRun] = []
  let first = parts[0]
  let mut right = first.right
  let mut lowY = first.y
  let mut highY = first.bottom
  for index, token in parts {
    let gap = if index == 0 { 0.0 } else { token.x - parts[index - 1].right }
    let value = if index > 0 &&
      gap > (token.size * 0.16).max(1) &&
      !parts[index - 1].text.has_suffix(" ") &&
      !token.text.has_prefix(" ") {
      " " + token.text
    } else {
      token.text
    }
    let run : PdfReadRun = {
      text: value,
      font: token.font,
      identity: token.identity,
      size: token.size,
      color: token.color,
      bold: token.bold,
      italic: token.italic,
    }
    if !runs.is_empty() {
      let prior = runs[runs.length() - 1]
      if prior.font == run.font &&
        prior.identity == run.identity &&
        prior.size == run.size &&
        prior.color == run.color &&
        prior.bold == run.bold &&
        prior.italic == run.italic {
        runs[runs.length() - 1] = { ..prior, text: prior.text + value, }
      } else {
        runs.push(run)
      }
    } else {
      runs.push(run)
    }
    right = right.max(token.right)
    lowY = lowY.min(token.y)
    highY = highY.max(token.bottom)
  }
  let cos = @math.cos(first.angle)
  let sin = @math.sin(first.angle)
  {
    runs,
    x: cos * first.x - sin * lowY,
    y: sin * first.x + cos * lowY,
    width: (right - first.x).max(0.1),
    height: (highY - lowY).max(first.size),
    rotation: first.angle * 180 / 3.141592653589793,
  }
}

///|
pub fn read_text_lines(
  extraction : PdfExtraction,
  families : Map[String, String],
  warnings : Array[String],
  page : Int32,
) -> Array[PdfReadLine] raise @failure.Failure {
  let groups : Map[String, Array[Token]] = Map([])
  let source = tokens(extraction, families, warnings, page)
  guard source.length() <= 262144 else {
    @failure.reject(
      "limit-exceeded", "PDF conversion text exceeds cluster budget",
    )
  }
  for token in source {
    let key = "\{(token.angle * 180 / 3.141592653589793).round().to_int()}:\{token.baseline.round().to_int()}"
    groups.get_or_init(key, () => []).push(token)
  }
  let lines : Array[PdfReadLine] = []
  for _, group in groups {
    group.sort_by((a, b) => a.x.compare(b.x))
    let mut active : Array[Token] = []
    for token in group {
      if !active.is_empty() &&
        token.x - active[active.length() - 1].right > (token.size * 2).max(18) {
        lines.push(finish_line(active))
        active = []
      }
      active.push(token)
    }
    if !active.is_empty() {
      lines.push(finish_line(active))
    }
  }
  lines.sort_by((a, b) => {
    if (a.y - b.y).abs() < 1 {
      a.x.compare(b.x)
    } else {
      a.y.compare(b.y)
    }
  })
  lines
}
