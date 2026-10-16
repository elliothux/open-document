///|
priv struct ValidationRule {
  kind : String
  operator : String
  ranges : Array[Range]
  first : String
  second : String
  blank : Bool
  style : String
  message : String
}

///|
fn validation_rule(
  tree : Tree,
  node : @xml.Node,
  ranges : Array[Range],
) -> ValidationRule raise @failure.Failure {
  let settings = validation_settings(tree, node)
  let title = String::from_array(settings.errorTitle.iter().take(32).to_array())
  let error = if settings.error.is_empty() {
    "Value does not satisfy data validation"
  } else {
    settings.error
  }
  {
    kind: settings.kind,
    operator: settings.operator,
    ranges,
    first: settings.formula1,
    second: settings.formula2,
    blank: settings.allowBlank,
    style: settings.errorStyle,
    message: (if title.is_empty() { "" } else { title + ": " }) +
    String::from_array(error.iter().take(255).to_array()),
  }
}

///|
fn validation_expression(
  source : String,
  anchor : Address,
  address : Address,
  sheets : Array[Sheet],
  sheet : Int,
  work : FormulaWork,
) -> Expression raise @failure.Failure {
  work.spend(amount=source.length())
  let source = source.strip_prefix("=").unwrap_or(source[:]).to_owned()
  try {
    let shifted = parse_formula(source).source(
      rows=address.row - anchor.row,
      columns=address.column - anchor.column,
      invalid_ref=true,
    )
    let expression = parse_formula(shifted)
    expression.dependencies(sheets, sheet, work, [], 0)
    expression
  } catch {
    @failure.Failure(code~, ..) if code != "limit-exceeded" =>
      @failure.reject(
        "protected-content", "Data validation formula requires unsupported calculation or references",
      )
    error => raise error
  }
}

///|
fn ValidationRule::accepts(
  self : ValidationRule,
  value : Value,
  address : Address,
  sheets : Array[Sheet],
  sheet : Int,
  calculation : Calculation,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  if self.blank && (value == Blank || value == Text("")) {
    return true
  }
  work.origin = address
  let anchor = rule_anchor(self.ranges, false)
  let first = validation_expression(
    self.first,
    anchor,
    address,
    sheets,
    sheet,
    work,
  )
  if self.kind == "list" {
    let values = validation_values(first, sheets, sheet, calculation, work)
    return values.any(item => {
      work.spend()
      if first is Constant(Text(_)) {
        item.display() == value.display()
      } else {
        item == value
      }
    })
  }
  let first = first.evaluate(sheets, sheet, calculation.values, work, 0)
  if self.kind == "custom" {
    return logical_value(first) == Boolean(true)
  }
  let actual = if self.kind == "textLength" {
    value.display().length().to_double()
  } else {
    guard value is Number(actual) else { return false }
    if self.kind == "whole" && actual.floor() != actual {
      return false
    }
    actual
  }
  guard numeric_value(first) is Number(low) else { return false }
  if self.operator == "between" || self.operator == "notBetween" {
    let expression = validation_expression(
      self.second,
      anchor,
      address,
      sheets,
      sheet,
      work,
    )
    guard numeric_value(
        expression.evaluate(sheets, sheet, calculation.values, work, 0),
      )
      is Number(high) else {
      return false
    }
    let inside = actual >= low && actual <= high
    return if self.operator == "between" { inside } else { !inside }
  }
  match self.operator {
    "equal" => actual == low
    "notEqual" => actual != low
    "lessThan" => actual < low
    "lessThanOrEqual" => actual <= low
    "greaterThan" => actual > low
    _ => actual >= low
  }
}

///|
fn Session::validate_inputs(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
  targets : Map[Int, Array[String]],
  accept_warnings : Bool,
) -> Unit raise @failure.Failure {
  let work = FormulaWork::{
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
  }
  let mut warning : (String, String)? = None
  let indices = targets.keys().to_array()
  indices.sort()
  for index in indices {
    let sheet = sheets[index]
    let tree = Tree::new(sheet.document)
    for node in sheet.document.nodes() {
      work.spend()
      guard !(["dataValidation", "dataValidations"].contains(node.name) &&
        node.uri != spreadsheet_uri) else {
        @failure.reject(
          "protected-content",
          "Extended data validation requires input validation support",
          part=sheet.id,
        )
      }
    }
    guard tree.one(tree.root("worksheet").id, "dataValidations")
      is Some(container) else {
      continue
    }
    let children = tree.children.get(container.id).unwrap_or([])
    guard children.length() <= 4096 &&
      children.all(n => n.uri == spreadsheet_uri && n.name == "dataValidation") else {
      @failure.reject(
        "protected-content",
        "Unknown or excessive data validations",
        part=sheet.id,
      )
    }
    let names = targets[index].copy()
    names.sort()
    let seen : Map[String, Bool] = Map([])
    for node in children {
      work.spend()
      let ranges = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
      let addresses = names
        .map(Address::parse)
        .filter(address => {
          ranges.any(range => {
            work.spend()
            range.contains(address)
          })
        })
      if addresses.is_empty() {
        continue
      }
      let addresses = addresses.filter(address => {
        let name = address.name()
        if seen.contains(name) {
          return false
        }
        seen[name] = true
        true
      })
      if addresses.is_empty() ||
        !flag(node, "showErrorMessage") ||
        node.attribute("type").unwrap_or("none") == "none" {
        continue
      }
      let rule = validation_rule(tree, node, ranges)
      for address in addresses {
        work.spend()
        let value = calculated_cell(sheets, calculation.values, index, address)
        if rule.accepts(value, address, sheets, index, calculation, work) {
          continue
        }
        let message = sheet.name +
          "!" +
          address.name() +
          ": " +
          (if rule.style == "stop" {
            "Validation stopped: "
          } else {
            "Validation warning: "
          }) +
          rule.message
        if rule.style == "stop" {
          @failure.reject("validation-stop", message, part=sheet.id)
        }
        if !accept_warnings && warning is None {
          warning = Some((sheet.id, message))
        }
      }
    }
  }
  if warning is Some((part, message)) {
    @failure.reject("validation-warning", message, part~)
  }
}
