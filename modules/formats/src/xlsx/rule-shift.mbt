///|
priv struct RuleShiftWork {
  mut cells : Int32
  mut units : Int32
  mut fragments : Int32
  mut source : Int32
  limit : Int32
}

///|
priv struct ShiftRuleField {
  node : @xml.Node
  attribute : Bool
  text : String
  expression : Expression?
}

///|
priv struct ShiftRuleGroup {
  anchor : Address
  texts : Array[String]
  expressions : Array[Expression?]
  mut ranges : Array[Range]
}

///|
fn shift_rule_expression(text : String) -> Expression? raise @failure.Failure {
  if text.trim().is_empty() {
    return None
  }
  let body = text.strip_prefix("=").unwrap_or(text[:]).to_owned()
  Some(parse_formula(body)) catch {
    @failure.Failure(code~, ..) if code != "limit-exceeded" =>
      @failure.reject(
        "protected-content", "Rule formula requires supported reference syntax",
      )
    error => raise error
  }
}

///|
fn FormulaAddress::rule_key(self : FormulaAddress, anchor : Address) -> Json {
  Json::array([
    Json(self.fixed_row),
    Json(self.fixed_column),
    Json(self.address.row - (if self.fixed_row { 0 } else { anchor.row })),
    Json(
      self.address.column - (if self.fixed_column { 0 } else { anchor.column }),
    ),
  ])
}

///|
fn Expression::rule_key(
  self : Expression,
  anchor : Address,
) -> Json raise @failure.Failure {
  match self {
    Structured(name, selector) =>
      Json::array([
        Json("table"),
        Json(name.map(String::to_upper)),
        Json(selector.to_upper()),
      ])
    Named(sheet, name) =>
      Json::array([Json("name"), Json(sheet), Json(name.to_upper())])
    Constant(_) => Json::array([Json("constant"), Json(self.source())])
    Reference(sheet, first, last) =>
      Json::array([
        Json("reference"),
        Json(sheet),
        first.rule_key(anchor),
        last.map(p => p.rule_key(anchor)).unwrap_or(Json::null()),
      ])
    Unary(op, value) => Json::array([Json(op), value.rule_key(anchor)])
    Binary(op, left, right) =>
      Json::array([Json(op), left.rule_key(anchor), right.rule_key(anchor)])
    Function(name, args) =>
      Json::array([Json(name), Json(args.map(v => v.rule_key(anchor)))])
  }
}

///|
fn Expression::relative_rule(self : Expression) -> Bool {
  match self {
    Structured(_, _) => true
    Named(_, _) => false
    Constant(_) => false
    Reference(_, first, last) =>
      !first.fixed_row ||
      !first.fixed_column ||
      last.map(p => !p.fixed_row || !p.fixed_column).unwrap_or(false)
    Unary(_, value) => value.relative_rule()
    Binary(_, left, right) => left.relative_rule() || right.relative_rule()
    Function(_, args) => args.any(Expression::relative_rule)
  }
}

///|
fn rule_expression_source(
  text : String,
  expression : Expression?,
  from : Address,
  into : Address,
  invalid~ : Bool,
) -> String raise @failure.Failure {
  if from == into || expression is None {
    return text
  }
  (if text.has_prefix("=") { "=" } else { "" }) +
  expression
  .unwrap()
  .source(
    rows=into.row - from.row,
    columns=into.column - from.column,
    invalid_ref=invalid,
  )
}

///|
fn AxisChange::source_position(
  self : AxisChange,
  address : Address,
) -> Address? {
  if self.band is Some((low, high)) {
    let value = if self.rows { address.column } else { address.row }
    if value < low || value > high {
      return Some(address)
    }
  }
  let value = if self.rows { address.row } else { address.column }
  let before = if value < self.first {
    value
  } else if self.insert {
    if value < self.first + self.count {
      return None
    }
    value - self.count
  } else {
    value + self.count
  }
  if before > self.limit() {
    return None
  }
  Some(
    if self.rows {
      { ..address, row: before, }
    } else {
      { ..address, column: before, }
    },
  )
}

///|
fn AxisChange::rule_ranges(
  self : AxisChange,
  before : Array[Range],
) -> Array[Range] raise @failure.Failure {
  let (low, high) = self.band.unwrap()
  let tail : Range = if self.rows {
    { top: self.first, bottom: 1048576, left: low, right: high, }
  } else {
    { top: low, bottom: high, left: self.first, right: 16384, }
  }
  let result = []
  for range in before {
    let (a, b) = if self.rows {
      (range.left, range.right)
    } else {
      (range.top, range.bottom)
    }
    if (a >= low && b <= high) || !range.intersects(tail) {
      if self.range(range) is Some(next) {
        result.push(next)
      }
    } else {
      let part : Range = {
        top: range.top.max(tail.top),
        bottom: range.bottom.min(tail.bottom),
        left: range.left.max(tail.left),
        right: range.right.min(tail.right),
      }
      if self.range(part) is Some(moved) {
        result.push(moved)
      }
      result.append(range.without(part))
    }
    guard result.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Shifted rule ranges exceed budget")
    }
  }
  result
}

///|
fn compact_shift_ranges(cells : Array[Range]) -> Array[Range] {
  cells.sort_by((a, b) => {
    let row = a.top.compare(b.top)
    if row == 0 {
      a.left.compare(b.left)
    } else {
      row
    }
  })
  let bands : Array[Range] = []
  for cell in cells {
    if bands.last() is Some(last) &&
      last.top == cell.top &&
      cell.left <= last.right + 1 {
      bands[bands.length() - 1] = { ..last, right: last.right.max(cell.right), }
    } else {
      bands.push(cell)
    }
  }
  let result : Array[Range] = []
  let previous : Map[(Int32, Int32), Int32] = Map([])
  for band in bands {
    let key = (band.left, band.right)
    if previous.get(key) is Some(index) && result[index].bottom + 1 == band.top {
      result[index] = { ..result[index], bottom: band.bottom, }
    } else {
      previous[key] = result.length()
      result.push(band)
    }
  }
  result
}

///|
fn shift_rule_fields(
  tree : Tree,
  rule : @xml.Node,
) -> Array[ShiftRuleField] raise @failure.Failure {
  let fields = []
  let pending = tree.children.get(rule.id).unwrap_or([]).copy()
  while pending.pop() is Some(node) {
    guard node.uri == spreadsheet_uri &&
      [
        "cfRule", "formula", "formula1", "formula2", "colorScale", "cfvo", "color",
        "dataBar", "iconSet",
      ].contains(node.name) else {
      @failure.reject(
        "protected-content", "Unknown rule structure prevents cell shifting",
      )
    }
    if ["formula", "formula1", "formula2"].contains(node.name) ||
      (node.name == "cfvo" && node.attribute("type") == Some("formula")) {
      let attribute = node.name == "cfvo"
      let text = if attribute {
        node.attribute("val").unwrap_or("")
      } else {
        node.text
      }
      fields.push({
        node,
        attribute,
        text,
        expression: shift_rule_expression(text),
      })
    }
    pending.append(tree.children.get(node.id).unwrap_or([]))
  }
  fields
}

///|
fn shift_rule_clone_guard(
  tree : Tree,
  rule : @xml.Node,
) -> Unit raise @failure.Failure {
  for node in tree.document.nodes() {
    if node.start < rule.start || node.end > rule.end {
      continue
    }
    let allowed = match node.name {
      "conditionalFormatting" => ["sqref", "pivot"]
      "cfRule" =>
        [
          "type", "dxfId", "priority", "stopIfTrue", "operator", "aboveAverage",
          "percent", "bottom", "rank", "stdDev", "equalAverage", "text", "timePeriod",
        ]
      "dataValidation" =>
        [
          "type", "errorStyle", "imeMode", "operator", "allowBlank", "showDropDown",
          "showInputMessage", "showErrorMessage", "errorTitle", "error", "promptTitle",
          "prompt", "sqref",
        ]
      "formula" | "formula1" | "formula2" => []
      "cfvo" => ["type", "val", "gte"]
      "color" => ["rgb", "indexed", "auto", "theme", "tint"]
      "colorScale" => []
      "dataBar" => ["minLength", "maxLength", "showValue"]
      "iconSet" => ["iconSet", "showValue", "percent", "reverse"]
      _ => []
    }
    guard node.attributes.all(a => a.uri.is_empty() && allowed.contains(a.name)) else {
      @failure.reject(
        "protected-content", "Unknown rule identity or attributes prevent splitting",
      )
    }
  }
}

///|
fn shift_rule_changes(
  tree : Tree,
  rule : @xml.Node,
  sheet : String,
  target : String,
  change : AxisChange,
  work : RuleShiftWork,
) -> (Array[@xml.SourceChange], Int32) raise @failure.Failure {
  let before = clear_rule_ranges(rule.attribute("sqref").unwrap_or(""))
  let after = if sheet == target {
    change.rule_ranges(before)
  } else {
    before.copy()
  }
  transform_rule_changes(
    tree,
    rule,
    after,
    at => if sheet == target { change.source_position(at) } else { Some(at) },
    text => axis_formula(text, Some(sheet), target, change),
    work,
  )
}

///|
fn transform_rule_changes(
  tree : Tree,
  rule : @xml.Node,
  after : Array[Range],
  source_position : (Address) -> Address?,
  transform : (String) -> String raise @failure.Failure,
  work : RuleShiftWork,
) -> (Array[@xml.SourceChange], Int32) raise @failure.Failure {
  let before = clear_rule_ranges(rule.attribute("sqref").unwrap_or(""))
  if after.is_empty() {
    return ([sheet_node_removal(tree, rule)], 0)
  }
  let conditional = rule.name == "conditionalFormatting"
  let original_anchor = rule_anchor(before, conditional)
  let next_anchor = rule_anchor(after, conditional)
  let source_anchor = source_position(next_anchor).unwrap_or(next_anchor)
  let fields = shift_rule_fields(tree, rule)
  if conditional &&
    tree.all(rule.id, "cfRule").length() > 1 &&
    fields.any(f => {
      !f.attribute &&
      f.expression.map(Expression::relative_rule).unwrap_or(false)
    }) {
    return transform_conditional_rules(
      tree, rule, after, source_position, transform, work,
    )
  }
  let evaluate = fn(at : Address) raise @failure.Failure {
    fields.map(field => {
      guard field.text.length() <= 4194304 - work.units else {
        @failure.reject(
          "limit-exceeded", "Rule formula shift work exceeds budget",
        )
      }
      work.units += field.text.length()
      transform(
        rule_expression_source(
          field.text,
          field.expression,
          original_anchor,
          if field.attribute {
            original_anchor
          } else {
            at
          },
          invalid=true,
        ),
      )
    })
  }
  let defaults = evaluate(source_anchor)
  let default_expressions = defaults.map(shift_rule_expression)
  let groups : Array[ShiftRuleGroup] = []
  if !fields.any(f => {
      !f.attribute &&
      f.expression.map(Expression::relative_rule).unwrap_or(false)
    }) {
    groups.push({
      anchor: next_anchor,
      texts: defaults,
      expressions: default_expressions,
      ranges: after,
    })
  } else {
    // shortcut: Relative rules use bounded cell evaluation; partition reference geometry when larger rules are required.
    let visited : Map[(Int32, Int32), Bool] = Map([])
    let indices : Map[String, Int32] = Map([])
    for range in after {
      guard (range.bottom - range.top + 1).to_int64() *
        (range.right - range.left + 1).to_int64() <=
        100000 else {
        @failure.reject(
          "limit-exceeded", "Relative rule shift exceeds the cell work budget",
        )
      }
      for row in range.top..<=range.bottom {
        for column in range.left..<=range.right {
          if visited.contains((row, column)) {
            continue
          }
          guard work.cells < 100000 else {
            @failure.reject(
              "limit-exceeded", "Relative rule shift exceeds the cell work budget",
            )
          }
          visited[(row, column)] = true
          work.cells += 1
          let at : Address = { row, column, }
          let source = source_position(at)
          let texts = if source is Some(source) {
            evaluate(source)
          } else {
            defaults.mapi((i, text) => {
              if fields[i].attribute {
                return text
              }
              rule_expression_source(
                text,
                default_expressions[i],
                next_anchor,
                at,
                invalid=true,
              )
            })
          }
          let expressions = texts.map(shift_rule_expression)
          let key = Json(
            expressions.mapi((i, e) => {
              e
              .map(e => {
                e.rule_key(
                  if fields[i].attribute {
                    original_anchor
                  } else {
                    at
                  },
                )
              })
              .unwrap_or(Json::null())
            }),
          ).stringify()
          let index = indices
            .get(key)
            .unwrap_or_else(() => {
              guard groups.length() < 4096 else {
                @failure.reject(
                  "limit-exceeded", "Shifted rule groups exceed budget",
                )
              }
              let index = groups.length()
              indices[key] = index
              groups.push({ anchor: at, texts, expressions, ranges: [], })
              index
            })
          groups[index].ranges.push({
            top: row,
            bottom: row,
            left: column,
            right: column,
          })
        }
      }
    }
    if groups.length() == 1 {
      groups[0].ranges = after
    } else {
      for group in groups {
        group.ranges = compact_shift_ranges(group.ranges)
      }
    }
  }
  let fragments : Array[Array[@xml.SourceChange]] = []
  let make = fn(
    group : ShiftRuleGroup,
    ranges : Array[Range],
  ) raise @failure.Failure {
    let anchor = rule_anchor(ranges, conditional)
    let changes = metadata_changes(rule, [
      (
        "sqref",
        if ranges == before {
          rule.attribute("sqref").unwrap()
        } else {
          ranges.map(Range::name).join(" ")
        },
      ),
    ])
    for i, field in fields {
      // Scale and bar thresholds belong to the whole rule, not each covered cell.
      let text = if field.attribute {
        group.texts[i]
      } else {
        rule_expression_source(
          group.texts[i],
          group.expressions[i],
          group.anchor,
          anchor,
          invalid=false,
        )
      }
      if field.expression.map(e => e.rule_key(original_anchor)) ==
        group.expressions[i].map(e => {
          e.rule_key(
            if field.attribute {
              original_anchor
            } else {
              group.anchor
            },
          )
        }) &&
        anchor == original_anchor {
        continue
      }
      changes.append(
        if field.attribute {
          metadata_changes(field.node, [("val", text)])
        } else {
          axis_text_change(tree, field.node, text)
        },
      )
    }
    changes
  }
  for group in groups {
    guard fragments.length() < 4096 - work.fragments else {
      @failure.reject("limit-exceeded", "Shifted rule fragments exceed budget")
    }
    fragments.push(make(group, group.ranges)) catch {
      @failure.Failure(code="invalid-address", ..) =>
        for range in group.ranges {
          guard fragments.length() < 4096 - work.fragments else {
            @failure.reject(
              "limit-exceeded", "Shifted rule fragments exceed budget",
            )
          }
          fragments.push(make(group, [range]))
        }
      error => raise error
    }
  }
  guard fragments.length() <= 4096 - work.fragments else {
    @failure.reject("limit-exceeded", "Shifted rule fragments exceed budget")
  }
  work.fragments += fragments.length()
  if fragments.length() == 1 {
    return (fragments[0], 1)
  }
  shift_rule_clone_guard(tree, rule)
  let output = StringBuilder()
  for edits in fragments {
    let scoped = edits.map(edit => {
      ..edit,
      node: rule.id,
      offset: tree.nodes[edit.node].start - rule.start + edit.offset,
    })
    let xml = style_markup(tree, rule, changes=scoped)
    guard xml.length() <= work.limit - work.source else {
      @failure.reject("limit-exceeded", "Shifted rule source exceeds budget")
    }
    work.source += xml.length()
    output.write_string(xml)
  }
  (
    [{ ..sheet_node_removal(tree, rule), xml: output.to_string(), }],
    fragments.length(),
  )
}

///|
fn shifted_rule_priorities(
  document : @xml.Document,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let rules = document
    .nodes()
    .filter(n => n.uri == spreadsheet_uri && n.name == "cfRule")
    .mapi((i, n) => {
      (natural(n.attribute("priority").unwrap_or(""), 2147483647), i, n)
    })
    .iter()
    .to_array()
  rules.sort_by((a, b) => {
    let priority = a.0.compare(b.0)
    if priority == 0 {
      a.1.compare(b.1)
    } else {
      priority
    }
  })
  let changes = []
  for i, (_, _, node) in rules {
    changes.append(metadata_changes(node, [("priority", (i + 1).to_string())]))
  }
  changes
}
