///|
pub(all) struct DataValidation {
  kind : String
  operator : String
  formula1 : String
  formula2 : String
  allowBlank : Bool
  showErrorMessage : Bool
  errorStyle : String
  errorTitle : String
  error : String
  showInputMessage : Bool
  promptTitle : String
  prompt : String
  showDropDown : Bool
} derive(Eq, ToJson)

///|
pub extend DataValidation with Eq::{equal, not_equal}

///|
pub extend DataValidation with ToJson::{to_json}

///|
pub fn DataValidation::default() -> DataValidation {
  {
    kind: "whole",
    operator: "between",
    formula1: "1",
    formula2: "10",
    allowBlank: true,
    showErrorMessage: true,
    errorStyle: "stop",
    errorTitle: "",
    error: "",
    showInputMessage: false,
    promptTitle: "",
    prompt: "",
    showDropDown: false,
  }
}

///|
fn validation_settings(
  tree : Tree,
  node : @xml.Node,
) -> DataValidation raise @failure.Failure {
  guard node.attributes.all(a => {
      a.uri.is_empty() &&
      [
        "type", "operator", "allowBlank", "showDropDown", "showInputMessage", "showErrorMessage",
        "errorStyle", "imeMode", "errorTitle", "error", "promptTitle", "prompt",
        "sqref",
      ].contains(a.name)
    }) &&
    node.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown data validation properties")
  }
  let kind = node.attribute("type").unwrap_or("none")
  let operator = node.attribute("operator").unwrap_or("between")
  let errorStyle = node.attribute("errorStyle").unwrap_or("stop")
  guard [
      "none", "whole", "decimal", "date", "time", "textLength", "list", "custom",
    ].contains(kind) &&
    [
      "between", "notBetween", "equal", "notEqual", "lessThan", "lessThanOrEqual",
      "greaterThan", "greaterThanOrEqual",
    ].contains(operator) &&
    ["stop", "warning", "information"].contains(errorStyle) else {
    @failure.reject(
      "protected-content", "Unsupported data validation type, operator or error style",
    )
  }
  guard tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => {
      n.uri == spreadsheet_uri &&
      ["formula1", "formula2"].contains(n.name) &&
      n.attributes.is_empty() &&
      tree.children.get(n.id).unwrap_or([]).is_empty()
    }) else {
    @failure.reject(
      "protected-content", "Unknown data validation formula markup",
    )
  }
  let formula1 = tree.one(node.id, "formula1").map(n => n.text).unwrap_or("")
  let formula2 = tree.one(node.id, "formula2").map(n => n.text).unwrap_or("")
  guard formula1.length() <= 8192 &&
    formula2.length() <= 8192 &&
    (
      kind == "none" ||
      (
        !formula1.is_empty() &&
        (
          !["between", "notBetween"].contains(operator) ||
          ["list", "custom"].contains(kind) ||
          !formula2.is_empty()
        )
      )
    ) else {
    @failure.reject(
      "protected-content", "Missing or excessive data validation formulas",
    )
  }
  {
    kind,
    operator,
    formula1,
    formula2,
    allowBlank: flag(node, "allowBlank"),
    showErrorMessage: flag(node, "showErrorMessage"),
    errorStyle,
    errorTitle: node.attribute("errorTitle").unwrap_or(""),
    error: node.attribute("error").unwrap_or(""),
    showInputMessage: flag(node, "showInputMessage"),
    promptTitle: node.attribute("promptTitle").unwrap_or(""),
    prompt: node.attribute("prompt").unwrap_or(""),
    showDropDown: flag(node, "showDropDown"),
  }
}

///|
fn DataValidation::check_metadata(
  self : DataValidation,
) -> Unit raise @failure.Failure {
  guard [
      "none", "whole", "decimal", "date", "time", "textLength", "list", "custom",
    ].contains(self.kind) &&
    [
      "between", "notBetween", "equal", "notEqual", "lessThan", "lessThanOrEqual",
      "greaterThan", "greaterThanOrEqual",
    ].contains(self.operator) &&
    ["stop", "warning", "information"].contains(self.errorStyle) &&
    [self.errorTitle, self.promptTitle].all(s => {
      s.length() <= 32 && @xml.valid_text(s)
    }) &&
    [self.error, self.prompt].all(s => s.length() <= 255 && @xml.valid_text(s)) &&
    [self.formula1, self.formula2].all(s => {
      s.length() <= 8192 && @xml.valid_text(s)
    }) &&
    (
      self.kind == "none" ||
      (
        !self.formula1.is_empty() &&
        (
          !["between", "notBetween"].contains(self.operator) ||
          ["list", "custom"].contains(self.kind) ||
          !self.formula2.is_empty()
        )
      )
    ) else {
    @failure.reject("invalid-operation", "Invalid data validation settings")
  }
}

///|
fn DataValidation::at(
  self : DataValidation,
  from : Address,
  to : Address,
) -> DataValidation raise @failure.Failure {
  {
    ..self,
    formula1: rule_formula(
      self.formula1,
      to.row - from.row,
      to.column - from.column,
    ),
    formula2: rule_formula(
      self.formula2,
      to.row - from.row,
      to.column - from.column,
    ),
  }
}

///|
fn DataValidation::markup(
  self : DataValidation,
  target : Range,
) -> String raise @failure.Failure {
  let fields = [
    ("type", self.kind),
    ("operator", self.operator),
    ("allowBlank", if self.allowBlank { "1" } else { "0" }),
    ("showErrorMessage", if self.showErrorMessage { "1" } else { "0" }),
    ("errorStyle", self.errorStyle),
    ("errorTitle", self.errorTitle),
    ("error", self.error),
    ("showInputMessage", if self.showInputMessage { "1" } else { "0" }),
    ("promptTitle", self.promptTitle),
    ("prompt", self.prompt),
    ("showDropDown", if self.showDropDown { "1" } else { "0" }),
    ("sqref", target.name()),
  ]
  let attributes = fields
    .map(p => " \{p.0}=\"\{escaped_attribute(p.1)}\"")
    .join("")
  let formulas = [("formula1", self.formula1), ("formula2", self.formula2)]
    .filter(p => !p.1.is_empty())
    .map(p => "<od:\{p.0}>\{@xml.escape_text(p.1)}</od:\{p.0}>")
    .join("")
  "<od:dataValidation xmlns:od=\"\{spreadsheet_uri}\"\{attributes}>\{formulas}</od:dataValidation>"
}
