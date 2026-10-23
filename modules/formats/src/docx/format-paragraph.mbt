///|
/// Paragraph distances are points; negative first-line indent creates a hanging indent.
pub(all) struct ParagraphFormat {
  style : FormatChange[String]
  align : FormatChange[String]
  rtl : FormatChange[Bool]
  before : FormatChange[Double]
  after : FormatChange[Double]
  left : FormatChange[Double]
  right : FormatChange[Double]
  first : FormatChange[Double]
  line : FormatChange[@layout.LineSpacing]
  tabs : FormatChange[Array[@layout.TabStop]]
  pageBreakBefore : FormatChange[Bool]
  keepLines : FormatChange[Bool]
  keepNext : FormatChange[Bool]
  widowControl : FormatChange[Bool]
}

///|
pub fn ParagraphFormat::new(
  style~ : FormatChange[String] = Keep,
  align~ : FormatChange[String] = Keep,
  rtl~ : FormatChange[Bool] = Keep,
  before~ : FormatChange[Double] = Keep,
  after~ : FormatChange[Double] = Keep,
  left~ : FormatChange[Double] = Keep,
  right~ : FormatChange[Double] = Keep,
  first~ : FormatChange[Double] = Keep,
  line~ : FormatChange[@layout.LineSpacing] = Keep,
  tabs~ : FormatChange[Array[@layout.TabStop]] = Keep,
  pageBreakBefore~ : FormatChange[Bool] = Keep,
  keepLines~ : FormatChange[Bool] = Keep,
  keepNext~ : FormatChange[Bool] = Keep,
  widowControl~ : FormatChange[Bool] = Keep,
) -> ParagraphFormat {
  {
    style,
    align,
    rtl,
    before,
    after,
    left,
    right,
    first,
    line,
    tabs,
    pageBreakBefore,
    keepLines,
    keepNext,
    widowControl,
  }
}

///|
fn ParagraphFormat::properties(
  self : ParagraphFormat,
) -> Map[String, Map[String, String?]?] raise @failure.Failure {
  let result : Map[String, Map[String, String?]?] = Map([])
  match self.style {
    Keep => ()
    Clear => result["pStyle"] = None
    Set(value) => {
      for
        name in [
          "jc", "spacing", "ind", "pageBreakBefore", "keepLines", "keepNext", "widowControl",
          "bidi", "outlineLvl", "contextualSpacing",
        ] {
        result[name] = None
      }
      result["pStyle"] = Some(Map::from_array([("val", Some(value))]))
    }
  }
  if self.tabs is Set(stops) {
    @layout.validate_tabs(stops)
  }
  match self.align {
    Keep => ()
    Clear => result["jc"] = None
    Set(value) => {
      guard ["left", "center", "right", "both"].contains(value) else {
        @failure.reject("invalid-operation", "Unsupported paragraph alignment")
      }
      result["jc"] = Some(Map::from_array([("val", Some(value))]))
    }
  }
  for
    (name, change) in [
      ("before", self.before),
      ("after", self.after),
      ("left", self.left),
      ("right", self.right),
      ("firstLine", self.first),
    ] {
    let group = if name == "before" || name == "after" {
      "spacing"
    } else {
      "ind"
    }
    let values = result.get(group).bind(value => value).unwrap_or(Map([]))
    match change {
      Keep => continue
      Clear => {
        values[name] = None
        if name == "firstLine" {
          values["hanging"] = None
        }
      }
      Set(value) => {
        guard value >= (if name == "firstLine" { -1584 } else { 0 }) &&
          value <= 1584 &&
          value * 20 == (value * 20).to_int().to_double() else {
          @failure.reject(
            "invalid-operation", "Paragraph distance must be in twips within 1584 points",
          )
        }
        if name == "firstLine" {
          values[if value < 0 { "hanging" } else { "firstLine" }] = Some(
            (value.abs() * 20).to_int().to_string(),
          )
          values[if value < 0 { "firstLine" } else { "hanging" }] = None
        } else {
          values[name] = Some((value * 20).to_int().to_string())
        }
      }
    }
    result[group] = Some(values)
  }
  for
    (name, change) in [
      ("pageBreakBefore", self.pageBreakBefore),
      ("keepLines", self.keepLines),
      ("keepNext", self.keepNext),
      ("widowControl", self.widowControl),
    ] {
    match change {
      Keep => ()
      Clear => result[name] = None
      Set(value) =>
        result[name] = Some(
          Map::from_array([("val", Some(if value { "1" } else { "0" }))]),
        )
    }
  }
  match self.rtl {
    Keep => ()
    Clear => result["bidi"] = None
    Set(value) =>
      result["bidi"] = Some(
        Map::from_array([("val", Some(if value { "1" } else { "0" }))]),
      )
  }
  let spacing = result.get("spacing").bind(value => value).unwrap_or(Map([]))
  match self.line {
    Keep => ()
    Clear => {
      spacing["line"] = None
      spacing["lineRule"] = None
      result["spacing"] = Some(spacing)
    }
    Set(value) => {
      let (rule, amount) = match value {
        @layout.Auto(value) => ("auto", value)
        @layout.Exact(value) => ("exact", value)
        @layout.AtLeast(value) => ("atLeast", value)
      }
      guard amount >= (if rule == "auto" { 120 } else { 1 }) &&
        amount <= (if rule == "auto" { 2400 } else { 31680 }) &&
        amount == amount.to_int().to_double() else {
        @failure.reject("invalid-operation", "Invalid paragraph line spacing")
      }
      spacing["line"] = Some(amount.to_int().to_string())
      spacing["lineRule"] = Some(rule)
      result["spacing"] = Some(spacing)
    }
  }
  result
}

///|
fn Session::format_paragraph_document(
  self : Session,
  document : @xml.Document,
  selection : Selection,
  patch : ParagraphFormat,
  fields~ : Bool = false,
) -> (@xml.Document, @xml.Edit)? raise @failure.Failure {
  let properties = patch.properties()
  let tree = WordTree::new(document)
  if patch.style is Set(key) {
    let styles = self.styles([])
    styles.validate_style(key, "paragraph")
    if styles.default_paragraph == Some(key) {
      properties["pStyle"] = None
    }
  }
  let range = self.formatting_range(
    document,
    selection,
    whole_cells=true,
    fields~,
    notes=true,
    math=true,
  )
  let changes : Array[@xml.SourceChange] = []
  for paragraph in range.paragraphs {
    let nested : Map[String, String] = Map([])
    match patch.tabs {
      Keep => if patch.style is Set(_) { nested["tabs"] = "" }
      Clear => nested["tabs"] = ""
      Set(stops) =>
        nested["tabs"] = self.tab_markup(
          tree,
          paragraph,
          stops,
          style=patch.style,
        )
    }
    let markup = formatted_properties(
      tree,
      document,
      paragraph,
      "pPr",
      properties,
      nested~,
    )
    if properties_change(tree, document, paragraph, "pPr", markup)
      is Some(change) {
      changes.push(change)
    }
  }
  if changes.is_empty() {
    None
  } else {
    let (candidate, edit) = document.edit_source(changes)
    if patch.style is (Set(_) | Clear) {
      for value in self.formatting_paragraphs(candidate, range.paragraphs) {
        guard value.readOnlyReason.is_empty() else {
          @failure.reject("protected-content", value.readOnlyReason)
        }
      }
    }
    Some((candidate, edit))
  }
}

///|
/// Applies paragraph properties to every paragraph touched by the explicit range.
pub fn Session::set_paragraph_format(
  self : Session,
  revision : Int,
  selection : Selection,
  patch : ParagraphFormat,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.apply_format(
    revision,
    selection,
    CharacterFormat::new(),
    patch,
    probe?,
    profile~,
    images?,
  )
}
