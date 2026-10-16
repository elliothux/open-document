///|
pub(all) struct ConditionalFormat {
  kind : String
  operator : String
  formula1 : String
  formula2 : String
  stopIfTrue : Bool
  format : CellFormat
  stops : Array[ConditionalStop]
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
  }
}

///|
fn CellFormat::patch_json(self : CellFormat) -> Json {
  let fields : Array[(String, Json?)] = [
    ("family", self.family.map(v => Json(v))),
    ("size", self.size.map(v => Json(v))),
    ("bold", self.bold.map(v => Json(v))),
    ("italic", self.italic.map(v => Json(v))),
    ("color", self.color.map(v => Json(v.to_lower()))),
    ("fill", self.fill.map(v => Json(v.to_lower()))),
    ("horizontal", self.horizontal.map(v => Json(v))),
    ("vertical", self.vertical.map(v => Json(v))),
    ("wrap", self.wrap.map(v => Json(v))),
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
  value
}

///|
fn ConditionalRule::settings(self : ConditionalRule) -> ConditionalFormat {
  {
    kind: self.kind,
    operator: self.operator,
    formula1: self.formulas.get(0).unwrap_or(""),
    formula2: self.formulas.get(1).unwrap_or(""),
    stopIfTrue: self.stop,
    format: self.style,
    stops: self.stops,
  }
}

///|
fn ConditionalFormat::check(
  self : ConditionalFormat,
  ranges : Array[Range],
  sheets : Array[Sheet],
  index : Int,
  work : FormulaWork,
) -> Unit raise @failure.Failure {
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
  priority : Int,
  style : Int?,
  colors~ : Array[String?] = [],
) -> String raise @failure.Failure {
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
  "<od:cfRule xmlns:od=\"\{spreadsheet_uri}\" type=\"\{self.kind}\" priority=\"\{priority}\"\{attributes}><od:formula>\{@xml.escape_text(self.formula1)}</od:formula>" +
  (if self.formula2.is_empty() {
    ""
  } else {
    "<od:formula>\{@xml.escape_text(self.formula2)}</od:formula>"
  }) +
  "</od:cfRule>"
}
