///|
pub(all) struct ConditionalFormat {
  kind : String
  operator : String
  formula1 : String
  formula2 : String
  stopIfTrue : Bool
  format : CellFormat
  stops : Array[ConditionalStop]
  bar : DataBar?
  icons : IconSet?
  rank : ConditionalRank?
  average : ConditionalAverage?
  text : String?
  timePeriod : String?
} derive(Eq)

///|
pub extend ConditionalFormat with Eq::{equal, not_equal}

///|
pub fn ConditionalFormat::default() -> ConditionalFormat {
  {
    kind: "cellIs",
    operator: "greaterThan",
    formula1: "0",
    formula2: "",
    stopIfTrue: false,
    format: CellFormat::new(fill=Some("fff2cc")),
    stops: [],
    bar: None,
    icons: None,
    rank: None,
    average: None,
    text: None,
    timePeriod: None,
  }
}

///|
fn CellFormat::patch_json(self : CellFormat) -> Json {
  let fields : Array[(String, Json?)] = [
    ("family", self.family.map(v => Json(v))),
    ("size", self.size.map(v => Json(v))),
    ("bold", self.bold.map(v => Json(v))),
    ("italic", self.italic.map(v => Json(v))),
    ("underline", self.underline.map(v => Json(v))),
    ("strike", self.strike.map(v => Json(v))),
    ("script", self.script.map(v => Json(v))),
    ("color", self.color.map(v => Json(v.to_lower()))),
    ("fill", self.fill.map(v => Json(v.to_lower()))),
    ("horizontal", self.horizontal.map(v => Json(v))),
    ("vertical", self.vertical.map(v => Json(v))),
    ("wrap", self.wrap.map(v => Json(v))),
    ("shrinkToFit", self.shrinkToFit.map(v => Json(v))),
    ("indent", self.indent.map(v => Json(v))),
    ("textRotation", self.textRotation.map(v => Json(v))),
    ("numberFormat", self.numberFormat.map(v => Json(v))),
  ]
  for
    (key, edge) in [
      ("left", self.left),
      ("right", self.right),
      ("top", self.top),
      ("bottom", self.bottom),
    ] {
    fields.push(
      (key, edge.map(edge => Json({ ..edge, color: edge.color.to_lower(), }))),
    )
  }
  let values : Map[String, Json] = Map([])
  for (key, value) in fields {
    if value is Some(value) {
      values[key] = value
    }
  }
  Json::object(values)
}

///|
fn ConditionalFormat::json(self : ConditionalFormat) -> Json {
  let value : Json = {
    "kind": self.kind,
    "operator": self.operator,
    "formula1": self.formula1,
    "formula2": self.formula2,
    "stopIfTrue": self.stopIfTrue,
    "format": self.format.patch_json(),
  }
  if !self.stops.is_empty() && value is Object(fields) {
    fields["stops"] = Json(
      self.stops.map(stop => { ..stop, color: stop.color.to_lower(), }),
    )
  }
  if self.bar is Some(bar) && value is Object(fields) {
    fields["bar"] = Json({ ..bar, color: bar.color.to_lower(), })
  }
  if self.icons is Some(icons) && value is Object(fields) {
    fields["icons"] = Json(icons)
  }
  if self.rank is Some(rank) && value is Object(fields) {
    fields["rank"] = Json(rank)
  }
  if self.average is Some(average) && value is Object(fields) {
    fields["average"] = Json(average)
  }
  if self.text is Some(text) && value is Object(fields) {
    fields["text"] = Json(text)
  }
  if self.timePeriod is Some(period) && value is Object(fields) {
    fields["timePeriod"] = Json(period)
  }
  value
}

///|
fn ConditionalRule::settings(self : ConditionalRule) -> ConditionalFormat {
  {
    kind: self.kind,
    operator: if conditional_text_kind(self.kind) {
      ""
    } else {
      self.operator
    },
    formula1: if conditional_predicate_kind(self.kind) ||
      conditional_text_kind(self.kind) ||
      self.kind == "timePeriod" {
      ""
    } else {
      self.formulas.get(0).unwrap_or("")
    },
    formula2: self.formulas.get(1).unwrap_or(""),
    stopIfTrue: self.stop,
    format: self.style,
    stops: self.stops,
    bar: self.bar,
    icons: self.icons,
    rank: self.rank,
    average: self.average,
    text: self.text,
    timePeriod: self.timePeriod,
  }
}

///|
fn ConditionalFormat::check(
  self : ConditionalFormat,
  ranges : Array[Range],
  sheets : Array[Sheet],
  index : Int32,
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  if self.check_nonformula() {
    self.format.validate()
    if self.text is Some(text) {
      ignore(
        conditional_text_formula(self.kind, text, rule_anchor(ranges, true)),
      )
    }
    return
  }
  if self.kind == "iconSet" {
    guard self.operator.is_empty() &&
      self.formula1.is_empty() &&
      self.formula2.is_empty() &&
      !self.stopIfTrue &&
      self.format == CellFormat::new() &&
      self.stops.is_empty() &&
      self.bar is None &&
      self.icons is Some(icons) else {
      @failure.reject(
        "invalid-operation", "Invalid conditional icon set settings",
      )
    }
    icons.check(rule_anchor(ranges, true), sheets, index, work)
    return
  }
  if self.kind == "dataBar" {
    guard self.operator.is_empty() &&
      self.formula1.is_empty() &&
      self.formula2.is_empty() &&
      !self.stopIfTrue &&
      self.format == CellFormat::new() &&
      self.stops.is_empty() &&
      self.bar is Some(bar) else {
      @failure.reject("invalid-operation", "Invalid data bar settings")
    }
    bar.check(rule_anchor(ranges, true), sheets, index, work)
    return
  }
  guard self.bar is None else {
    @failure.reject("invalid-operation", "Only data bars have bar settings")
  }
  if self.kind == "colorScale" {
    guard self.operator.is_empty() &&
      self.formula1.is_empty() &&
      self.formula2.is_empty() &&
      !self.stopIfTrue &&
      self.format == CellFormat::new() &&
      [2, 3].contains(self.stops.length()) else {
      @failure.reject("invalid-operation", "Invalid color scale settings")
    }
    for stop in self.stops {
      stop.check(rule_anchor(ranges, true), sheets, index, work)
    }
    return
  }
  guard self.stops.is_empty() else {
    @failure.reject(
      "invalid-operation", "Highlight rules have no color scale stops",
    )
  }
  guard (self.kind == "expression" && self.operator.is_empty()) ||
    (
      self.kind == "cellIs" &&
      [
        "between", "notBetween", "equal", "notEqual", "greaterThan", "greaterThanOrEqual",
        "lessThan", "lessThanOrEqual",
      ].contains(self.operator)
    ) else {
    @failure.reject(
      "invalid-operation", "Invalid conditional format kind or operator",
    )
  }
  let pair = self.kind == "cellIs" &&
    ["between", "notBetween"].contains(self.operator)
  guard !self.formula1.is_empty() &&
    self.formula1.length() <= 8192 &&
    self.formula2.length() <= 8192 &&
    (if pair { !self.formula2.is_empty() } else { self.formula2.is_empty() }) &&
    @xml.valid_text(self.formula1) &&
    @xml.valid_text(self.formula2) else {
    @failure.reject("invalid-operation", "Invalid conditional format formulas")
  }
  self.format.validate()
  let anchor = rule_anchor(ranges, true)
  for formula in [self.formula1, self.formula2] {
    if !formula.is_empty() {
      ignore(rule_expression(formula, anchor, anchor, sheets, index, work))
    }
  }
}

///|
fn ConditionalFormat::markup(
  self : ConditionalFormat,
  priority : Int32,
  style : Int32?,
  anchor : Address,
  colors~ : Array[String?] = [],
) -> String raise @failure.Failure {
  if self.icons is Some(icons) {
    return icons.markup(priority)
  }
  if self.kind == "dataBar" && self.bar is Some(bar) {
    let thresholds = [bar.minimum, bar.maximum]
      .map(stop => {
        "<od:cfvo type=\"\{stop.kind}\"" +
        (if stop.value.is_empty() {
          ""
        } else {
          " val=\"\{escaped_attribute(stop.value)}\""
        }) +
        "/>"
      })
      .join("")
    let color = colors
      .get(0)
      .bind(value => value)
      .unwrap_or("<od:color rgb=\"FF\{bar.color.to_upper()}\"/>")
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"dataBar\" priority=\"\{priority}\"><od:dataBar minLength=\"\{bar.minLength}\" maxLength=\"\{bar.maxLength}\" showValue=\"\{if bar.showValue { "1" } else { "0" }}\">\{thresholds}\{color}</od:dataBar></od:cfRule>"
  }
  if self.kind == "colorScale" {
    let thresholds = self.stops
      .map(stop => {
        "<od:cfvo type=\"\{stop.kind}\"" +
        (if stop.value.is_empty() {
          ""
        } else {
          " val=\"\{escaped_attribute(stop.value)}\""
        }) +
        "/>"
      })
      .join("")
    let palette = self.stops
      .mapi((i, stop) => {
        colors
        .get(i)
        .bind(value => value)
        .unwrap_or("<od:color rgb=\"FF\{stop.color.to_upper()}\"/>")
      })
      .join("")
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"colorScale\" priority=\"\{priority}\"><od:colorScale>\{thresholds}\{palette}</od:colorScale></od:cfRule>"
  }
  let attributes = (if self.kind == "cellIs" {
      " operator=\"\{self.operator}\""
    } else {
      ""
    }) +
    (if self.stopIfTrue { " stopIfTrue=\"1\"" } else { "" }) +
    style.map(id => " dxfId=\"\{id}\"").unwrap_or("")
  if self.text is Some(text) {
    let formula = conditional_text_formula(self.kind, text, anchor)
    let operator = if self.kind == "notContainsText" {
      "notContains"
    } else {
      self.kind
    }
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"\{self.kind}\" priority=\"\{priority}\"\{attributes} operator=\"\{operator}\" text=\"\{escaped_attribute(text)}\"><od:formula>\{@xml.escape_text(formula)}</od:formula></od:cfRule>"
  }
  if conditional_predicate_formula(self.kind, anchor) is Some(formula) {
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"\{self.kind}\" priority=\"\{priority}\"\{attributes}><od:formula>\{@xml.escape_text(formula)}</od:formula></od:cfRule>"
  }
  if self.timePeriod is Some(period) {
    let formula = conditional_date_formula(period, anchor)
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"timePeriod\" timePeriod=\"\{period}\" priority=\"\{priority}\"\{attributes}><od:formula>\{@xml.escape_text(formula)}</od:formula></od:cfRule>"
  }
  if self.kind == "duplicateValues" || self.kind == "uniqueValues" {
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"\{self.kind}\" priority=\"\{priority}\"\{attributes}/>"
  }
  if self.rank is Some(rank) {
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"top10\" priority=\"\{priority}\"\{attributes} rank=\"\{rank.rank}\" percent=\"\{if rank.percent {1} else {0}}\" bottom=\"\{if rank.bottom {1} else {0}}\"/>"
  }
  if self.average is Some(average) {
    return "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"aboveAverage\" priority=\"\{priority}\"\{attributes} aboveAverage=\"\{if average.above {1} else {0}}\" equalAverage=\"\{if average.equal {1} else {0}}\" stdDev=\"\{average.stdDev}\"/>"
  }
  "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"\{self.kind}\" priority=\"\{priority}\"\{attributes}><od:formula>\{@xml.escape_text(self.formula1)}</od:formula>" +
  (if self.formula2.is_empty() {
    ""
  } else {
    "<od:formula>\{@xml.escape_text(self.formula2)}</od:formula>"
  }) +
  "</od:cfRule>"
}
