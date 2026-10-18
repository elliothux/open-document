///|
priv struct ConditionalRule {
  node : Int
  container : Int
  ranges : Array[Range]
  anchor : Address
  kind : String
  operator : String
  formulas : Array[String]
  priority : Int
  stop : Bool
  style : CellFormat
  stops : Array[ConditionalStop]
  bar : DataBar?
}

///|
priv struct ConditionalRules {
  table_styles : TableStyles
  rules : Array[ConditionalRule]
  reason : String
  scales : Map[Int, Array[Double]]
}

///|
fn Session::conditional_rules(
  self : Session,
  current : Sheet,
  index : Int,
  sheets : Array[Sheet],
  work : FormulaWork,
  parts~ : Map[String, @xml.Document] = self.parts,
) -> ConditionalRules raise @failure.Failure {
  let table_styles = self.table_styles(current, work, parts)
  try {
    let tree = Tree::new(current.document)
    let rules : Array[ConditionalRule] = []
    let priorities : Map[Int, Bool] = Map([])
    let styles : Map[Int, CellFormat] = Map([])
    let mut differential : Tree? = None
    let mut nodes : Array[@xml.Node] = []
    for node in current.document.nodes() {
      guard node.name != "conditionalFormatting" || node.uri == spreadsheet_uri else {
        @failure.reject(
          "protected-content", "Extended conditional formatting is unsupported",
        )
      }
    }
    for
      container in tree.all(tree.root("worksheet").id, "conditionalFormatting") {
      conditional_node(tree, container, ["sqref", "pivot"], ["cfRule"])
      guard !flag(container, "pivot") else {
        @failure.reject(
          "protected-content", "Pivot conditional formatting is unsupported",
        )
      }
      let source = container.attribute("sqref").unwrap_or("")
      work.spend(amount=source.length())
      let ranges = clear_rule_ranges(source)
      let anchor = rule_anchor(ranges, true)
      for node in tree.all(container.id, "cfRule") {
        work.spend()
        guard rules.length() < 4096 else {
          @failure.reject(
            "limit-exceeded", "Conditional rule count exceeds 4096",
          )
        }
        conditional_node(
          tree,
          node,
          ["type", "operator", "priority", "stopIfTrue", "dxfId"],
          ["formula", "colorScale", "dataBar"],
        )
        let kind = node.attribute("type").unwrap_or("")
        let operator = node.attribute("operator").unwrap_or("")
        guard (
            ["expression", "colorScale", "dataBar"].contains(kind) &&
            operator.is_empty()
          ) ||
          (
            kind == "cellIs" &&
            [
              "between", "notBetween", "equal", "notEqual", "greaterThan", "greaterThanOrEqual",
              "lessThan", "lessThanOrEqual",
            ].contains(operator)
          ) else {
          @failure.reject(
            "protected-content",
            "Unsupported conditional formatting rule: " + kind,
          )
        }
        let priority = natural(
          node.attribute("priority").unwrap_or(""),
          2147483647,
        )
        guard priority > 0 && !priorities.contains(priority) else {
          @failure.reject(
            "malformed-xlsx", "Invalid or duplicate conditional priority",
          )
        }
        priorities[priority] = true
        let formulas = tree
          .all(node.id, "formula")
          .map(formula => {
            conditional_node(tree, formula, [], [])
            guard !formula.text.is_empty() && formula.text.length() <= 8192 else {
              @failure.reject(
                "protected-content", "Invalid conditional formula length",
              )
            }
            ignore(
              rule_expression(formula.text, anchor, anchor, sheets, index, work),
            )
            formula.text
          })
        guard formulas.length() ==
          (if kind == "colorScale" || kind == "dataBar" {
            0
          } else if operator == "between" || operator == "notBetween" {
            2
          } else {
            1
          }) else {
          @failure.reject("malformed-xlsx", "Invalid conditional formula count")
        }
        let mut style = CellFormat::new()
        let scale = tree.one(node.id, "colorScale")
        let bar = tree.one(node.id, "dataBar")
        guard (kind == "dataBar") == (bar is Some(_)) else {
          @failure.reject("malformed-xlsx", "Mismatched conditional data bar")
        }
        let bar = bar.map(bar => {
          guard node.attribute("dxfId") is None && !flag(node, "stopIfTrue") else {
            @failure.reject(
              "protected-content", "Data bar differential or stop flags are unsupported",
            )
          }
          read_conditional_bar(
            tree,
            bar,
            self.theme,
            anchor,
            sheets,
            index,
            work,
          )
        })
        guard (kind == "colorScale") == (scale is Some(_)) else {
          @failure.reject(
            "malformed-xlsx", "Mismatched conditional color scale",
          )
        }
        let stops = if scale is Some(scale) {
          guard node.attribute("dxfId") is None && !flag(node, "stopIfTrue") else {
            @failure.reject(
              "protected-content", "Color scale differential or stop flags are unsupported",
            )
          }
          read_conditional_scale(
            tree,
            scale,
            self.theme,
            anchor,
            sheets,
            index,
            work,
          )
        } else {
          []
        }
        if node.attribute("dxfId") is Some(raw) {
          let id = natural(raw, 4095)
          if styles.get(id) is Some(cached) {
            style = cached
          } else {
            if differential is None {
              guard self.styles_part(parts) is Some(part) else {
                @failure.reject(
                  "malformed-xlsx", "Missing conditional styles part",
                )
              }
              let source = Tree::new(
                parts.get(part).unwrap_or_else(() => self.opc.xml(part)),
              )
              let root = source.root("styleSheet")
              nodes = source
                .one(root.id, "dxfs")
                .map(parent => {
                  conditional_node(source, parent, ["count"], ["dxf"])
                  source.all(parent.id, "dxf")
                })
                .unwrap_or([])
              guard nodes.length() <= 4096 else {
                @failure.reject(
                  "limit-exceeded", "Conditional styles exceed 4096",
                )
              }
              differential = Some(source)
            }
            guard nodes.get(id) is Some(dxf) else {
              @failure.reject("malformed-xlsx", "Missing conditional style")
            }
            style = conditional_style(differential.unwrap(), dxf, self.theme)
            styles[id] = style
          }
        }
        rules.push({
          node: node.id,
          container: container.id,
          ranges,
          anchor,
          kind,
          operator,
          formulas,
          priority,
          style,
          stops,
          bar,
          stop: flag(node, "stopIfTrue"),
        })
      }
    }
    rules.sort_by((a, b) => a.priority.compare(b.priority))
    { rules, table_styles, reason: "", scales: Map([]), }
  } catch {
    @failure.Failure(code~, message~, ..) if code != "limit-exceeded" =>
      { rules: [], table_styles, reason: message, scales: Map([]), }
    error => raise error
  }
}

///|
fn conditional_compare(operator : String, value : Value, first : Value) -> Bool {
  // cellIs keeps numbers, text and booleans distinct; blank is zero or empty text.
  let equal = match (value, first) {
    (Blank | Text(""), Number(number)) => number == 0
    (Blank | Text(""), Text(text)) => text.is_empty()
    (Number(a), Number(b)) => a == b
    (Text(a), Text(b)) => a.to_lower() == b.to_lower()
    (Boolean(a), Boolean(b)) => a == b
    _ => false
  }
  let greater = match (value, first) {
    (Blank | Text(""), Number(number)) => 0.0 > number
    (Blank | Text(""), Text(text)) => "".compare(text.to_lower()) > 0
    (Number(a), Number(b)) => a > b
    (_, Number(_)) => true
    (Text(a), Text(b)) => a.to_lower().compare(b.to_lower()) > 0
    (Boolean(_), Text(_)) => true
    (Boolean(a), Boolean(b)) => a && !b
    _ => false
  }
  match operator {
    "equal" => equal
    "notEqual" => !equal
    "greaterThan" => greater
    "greaterThanOrEqual" => greater || equal
    "lessThan" => !(greater || equal)
    _ => !greater
  }
}

///|
fn ConditionalRules::applied(
  self : ConditionalRules,
  source : CellStyle,
  address : Address,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> CellStyle raise @failure.Failure {
  let source = self.table_styles.applied(source, sheets[index], address)
  work.spend(amount=self.table_styles.tables.length())
  try {
    guard self.reason.is_empty() else {
      return { ..source, diagnostic: self.reason, }
    }
    let matched : Array[CellFormat] = []
    let mut bar : ConditionalBar? = None
    for rule in self.rules {
      work.spend()
      if !rule.ranges.any(range => {
          work.spend()
          range.contains(address)
        }) {
        continue
      }
      work.origin = address
      if rule.kind == "dataBar" {
        if bar is None {
          bar = self.data_bar(rule, address, sheets, index, values, work)
        }
        continue
      }
      if rule.kind == "colorScale" {
        if self.scale_fill(rule, address, sheets, index, values, work)
          is Some(color) {
          matched.push(CellFormat::new(fill=Some(color)))
        }
        continue
      }
      let first = rule_expression(
        rule.formulas[0],
        rule.anchor,
        address,
        sheets,
        index,
        work,
      ).evaluate(sheets, index, values, work, 0)
      if first is Error(_) {
        continue
      }
      let accepted = if rule.kind == "expression" {
        logical_value(first) == Boolean(true)
      } else {
        let actual = calculated_cell(sheets, values, index, address)
        if actual is Error(_) {
          continue
        }
        if rule.operator == "between" || rule.operator == "notBetween" {
          let second = rule_expression(
            rule.formulas[1],
            rule.anchor,
            address,
            sheets,
            index,
            work,
          ).evaluate(sheets, index, values, work, 0)
          if second is Error(_) {
            continue
          }
          let inside = conditional_compare("greaterThanOrEqual", actual, first) &&
            conditional_compare("lessThanOrEqual", actual, second)
          if rule.operator == "between" {
            inside
          } else {
            !inside
          }
        } else {
          conditional_compare(rule.operator, actual, first)
        }
      }
      if accepted {
        matched.push(rule.style)
        if rule.stop {
          break
        }
      }
    }
    let mut result = source
    // Apply the highest priority last, preserving non-conflicting lower properties.
    for style in matched.rev() {
      result = style.applied(result)
      let priorities = result.border_priority.copy()
      for side, patch in [style.left, style.right, style.top, style.bottom] {
        if patch is Some(_) {
          priorities[side] = 2
        }
      }
      result = { ..result, border_priority: priorities, }
    }
    { ..result, bar, }
  } catch {
    @failure.Failure(code~, message~, ..) if code != "limit-exceeded" =>
      { ..source, diagnostic: message, }
    error => raise error
  }
}
