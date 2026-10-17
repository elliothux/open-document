///|
pub(all) struct TextSpacing {
  unit : String
  value : Double
}

///|
pub(all) struct ParagraphFormat {
  left : Double?
  right : Double?
  first : Double?
  before : TextSpacing?
  after : TextSpacing?
  line : TextSpacing?
  list : ListFormat?
  level : Int?
  rtl : Bool?
}

///|
pub fn ParagraphFormat::new(
  left? : Double,
  right? : Double,
  first? : Double,
  before? : TextSpacing,
  after? : TextSpacing,
  line? : TextSpacing,
  list? : ListFormat,
  level? : Int,
  rtl? : Bool,
) -> ParagraphFormat {
  { left, right, first, before, after, line, list, level, rtl, }
}

///|
fn TextSpacing::normalized(
  self : TextSpacing,
  line~ : Bool = false,
) -> TextSpacing raise @failure.Failure {
  guard ["point", "percent"].contains(self.unit) &&
    !self.value.is_nan() &&
    !self.value.is_inf() else {
    @failure.reject("invalid-operation", "Invalid paragraph spacing")
  }
  let factor = if self.unit == "point" { 100.0 } else { 1000.0 }
  guard self.value >= (if line { 1 / factor } else { 0 }) &&
    self.value <= (if self.unit == "point" { 1584 } else { 1000 }) else {
    @failure.reject("invalid-operation", "Paragraph spacing exceeds its range")
  }
  { ..self, value: (self.value * factor).round() / factor, }
}

///|
fn ParagraphFormat::normalized(
  self : ParagraphFormat,
) -> ParagraphFormat raise @failure.Failure {
  guard self.left is Some(_) ||
    self.right is Some(_) ||
    self.first is Some(_) ||
    self.before is Some(_) ||
    self.after is Some(_) ||
    self.line is Some(_) ||
    self.list is Some(_) ||
    self.level is Some(_) ||
    self.rtl is Some(_) else {
    @failure.reject("invalid-operation", "Specify a paragraph property")
  }
  if self.list is Some(list) {
    list.check()
  }
  if self.level is Some(level) {
    guard level >= 0 && level <= 8 else {
      @failure.reject("invalid-operation", "List level must be 0..8")
    }
  }
  for
    (value, minimum) in [
      (self.left, 0.0),
      (self.right, 0.0),
      (self.first, -4032.0),
    ] {
    if value is Some(value) {
      guard !value.is_nan() &&
        !value.is_inf() &&
        value >= minimum &&
        value <= 4032 else {
        @failure.reject("invalid-operation", "Invalid paragraph indentation")
      }
    }
  }
  {
    left: self.left.map(v => (v * 12700).round() / 12700),
    right: self.right.map(v => (v * 12700).round() / 12700),
    first: self.first.map(v => (v * 12700).round() / 12700),
    before: self.before.map(v => v.normalized()),
    after: self.after.map(v => v.normalized()),
    line: self.line.map(v => v.normalized(line=true)),
    list: self.list,
    level: self.level,
    rtl: self.rtl,
  }
}

///|
fn spacing_value(value : ParagraphGap) -> Json {
  match value {
    Points(value) => { "unit": "point", "value": value }
    Percent(value) =>
      { "unit": "percent", "value": (value * 100000).round() / 1000 }
  }
}

///|
fn paragraph_values(paragraph : TextParagraph) -> Array[Json] {
  [
    Json(paragraph.left),
    Json(paragraph.right),
    Json(paragraph.first),
    spacing_value(paragraph.before),
    spacing_value(paragraph.after),
    match paragraph.spacing {
      Auto(value) =>
        { "unit": "percent", "value": (value * 100000 / 240).round() / 1000 }
      Exact(value) | AtLeast(value) => { "unit": "point", "value": value / 20 }
    },
    paragraph.list.query(),
    Json(paragraph.level),
    Json(paragraph.rtl),
  ]
}

///|
fn paragraph_markup(
  paragraph : TextParagraph,
  format : ParagraphFormat?,
) -> String raise @failure.Failure {
  let properties = paragraph.source.child("pPr")
  guard format is Some(format) else {
    return if properties is Some(p) &&
      has_direct_properties(Some(p), paragraph=true) {
      cleared_properties(p, paragraph=true)
    } else {
      ""
    }
  }
  let attrs : Map[String, String] = Map([])
  let changes : Map[String, String] = Map([])
  if format.rtl is Some(rtl) && rtl != paragraph.rtl {
    attrs["rtl"] = if rtl { "1" } else { "0" }
    // ONLYOFFICE mirrors left/right alignment when switching DrawingML direction.
    if paragraph.align == "left" {
      attrs["algn"] = "r"
    } else if paragraph.align == "right" {
      attrs["algn"] = "l"
    }
  }
  let mut left = format.left
  let mut first = format.first
  if format.list is Some(list) && list != paragraph.list {
    if properties is Some(p) {
      check_list_properties(p)
    }
    for name in ["buNone", "buChar", "buAutoNum"] {
      changes[name] = ""
    }
    let (name, markup) = list_markup(list)
    changes[name] = markup
    // ONLYOFFICE anchors a new list at the old left edge with a font-sized hanging indent.
    let base = paragraph.left.min(paragraph.left + paragraph.first).max(0)
    if list is NoList {
      left = Some(left.unwrap_or(base))
      first = Some(first.unwrap_or(0))
    } else if paragraph.list is NoList {
      let indent = (paragraph.runs[0].style().size * 0.305954545 + 2.378363636) *
        72 /
        25.4
      left = Some(left.unwrap_or(base + indent))
      first = Some(first.unwrap_or(-indent))
    }
  }
  if format.level is Some(level) && level != paragraph.level {
    attrs["lvl"] = level.to_string()
  }
  let current = paragraph_values(paragraph)
  for
    (name, value, effective) in [
      ("marL", left, paragraph.left),
      ("marR", format.right, paragraph.right),
      ("indent", first, paragraph.first),
    ] {
    if value is Some(value) && value != effective {
      attrs[name] = (value * 12700).round().to_int().to_string()
    }
  }
  for
    (name, value, index) in [
      ("spcBef", format.before, 3),
      ("spcAft", format.after, 4),
      ("lnSpc", format.line, 5),
    ] {
    if value is Some(value) &&
      current[index] != { "unit": value.unit, "value": value.value } {
      let kind = if value.unit == "point" { "spcPts" } else { "spcPct" }
      let number = (value.value *
        (if value.unit == "point" { 100 } else { 1000 }))
        .round()
        .to_int()
      changes[name] = "<a:\{name} xmlns:a=\"\{drawing_uri}\"><a:\{kind} val=\"\{number}\"/></a:\{name}>"
    }
  }
  if attrs.is_empty() && changes.is_empty() {
    return ""
  }
  let output = StringBuilder()
  let order = [
    "lnSpc", "spcBef", "spcAft", "buClrTx", "buClr", "buSzTx", "buSzPct", "buSzPts",
    "buFontTx", "buFont", "buNone", "buChar", "buAutoNum", "tabLst", "defRPr", "extLst",
  ]
  let mut qualified = "a:pPr"
  if properties is Some(p) {
    qualified = p.node.qualified
    output.write_string(frame_opening(p, attrs))
    if !p.node.empty {
      let source = p.tree.document.source()
      let mut offset = p.node.opening_end
      for child in p.tree.children.get(p.node.id).unwrap_or([]) {
        output.write_view(source[offset:child.start])
        for name in order[:order.search(child.name).unwrap_or(order.length())] {
          if changes.get(name) is Some(markup) {
            output.write_string(markup)
            ignore(changes.remove(name))
          }
        }
        if changes.get(child.name) is Some(markup) && child.uri == drawing_uri {
          output.write_string(markup)
          ignore(changes.remove(child.name))
        } else {
          output.write_view(source[child.start:child.end])
        }
        offset = child.end
      }
      output.write_view(source[offset:p.node.closing_start])
    }
  } else {
    output.write_string("<a:pPr xmlns:a=\"\{drawing_uri}\"")
    for name, value in attrs {
      output.write_string(" \{name}=\"\{value}\"")
    }
    output.write_string(">")
  }
  for name in order {
    if changes.get(name) is Some(markup) {
      output.write_string(markup)
    }
  }
  output.write_string("</\{qualified}>")
  output.to_string()
}
