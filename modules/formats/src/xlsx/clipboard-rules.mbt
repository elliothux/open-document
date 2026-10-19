///|
pub(all) struct CopiedConditional {
  ranges : Array[Range]
  anchor : Address
  settings : ConditionalFormat
}

///|
pub(all) struct CopiedValidation {
  ranges : Array[Range]
  anchor : Address
  settings : DataValidation
}

///|
fn CopiedCells::check_copied_rules(
  self : CopiedCells,
) -> Unit raise @failure.Failure {
  guard self.conditional.length() <= 4096 && self.validations.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Copied rule count exceeds budget")
  }
  let bounds : Range = {
    top: self.top,
    left: self.left,
    bottom: self.top + self.cells.length() - 1,
    right: self.left + self.cells[0].length() - 1,
  }
  let mut units = 0
  let mut count = 0
  let check = fn(
    ranges : Array[Range],
    anchor : Address,
    text : String,
  ) raise @failure.Failure {
    guard !ranges.is_empty() &&
      ranges.length() <= 4096 &&
      anchor.row >= 1 &&
      anchor.row <= 1048576 &&
      anchor.column >= 1 &&
      anchor.column <= 16384 else {
      @failure.reject("invalid-operation", "Invalid copied rule geometry")
    }
    for range in ranges {
      guard range.top <= range.bottom &&
        range.left <= range.right &&
        bounds.covers(range) else {
        @failure.reject(
          "invalid-operation", "Copied rule leaves source rectangle",
        )
      }
    }
    count += ranges.length()
    units += text.length()
    guard count <= 4096 && units <= 1048576 else {
      @failure.reject("limit-exceeded", "Copied rule payload exceeds budget")
    }
  }
  for rule in self.conditional {
    let settings = rule.settings
    settings.format.validate()
    guard ["expression", "cellIs", "colorScale", "dataBar"].contains(
        settings.kind,
      ) &&
      [
        "", "between", "notBetween", "equal", "notEqual", "lessThan", "lessThanOrEqual",
        "greaterThan", "greaterThanOrEqual",
      ].contains(settings.operator) &&
      settings.stops.length() <= 3 else {
      @failure.reject(
        "invalid-operation", "Invalid copied conditional settings",
      )
    }
    let texts = [settings.formula1, settings.formula2]
    texts.append(settings.stops.map(stop => stop.value))
    let kinds = settings.stops.map(stop => stop.kind)
    let colors = settings.stops.map(stop => stop.color)
    if settings.bar is Some(bar) {
      texts.append([bar.minimum.value, bar.maximum.value])
      kinds.append([bar.minimum.kind, bar.maximum.kind])
      colors.push(bar.color)
    }
    guard kinds.all(kind => {
        ["min", "max", "num", "percent", "percentile", "formula"].contains(kind)
      }) &&
      colors.all(color => {
        color.length() == 6 && color.iter().all(ch => ch.is_ascii_hexdigit())
      }) else {
      @failure.reject(
        "invalid-operation", "Invalid copied conditional thresholds or colors",
      )
    }
    guard texts.all(text => text.length() <= 8192 && @xml.valid_text(text)) else {
      @failure.reject(
        "limit-exceeded", "Copied conditional formula exceeds budget",
      )
    }
    check(rule.ranges, rule.anchor, settings.json().stringify())
  }
  for rule in self.validations {
    rule.settings.check_metadata()
    check(rule.ranges, rule.anchor, Json(rule.settings).stringify())
  }
}

///|
fn Range::clipboard_intersections(
  self : Range,
  ranges : Array[Range],
) -> Array[Range] {
  ranges
  .filter(r => self.intersects(r))
  .map(r => {
    top: r.top.max(self.top),
    bottom: r.bottom.min(self.bottom),
    left: r.left.max(self.left),
    right: r.right.min(self.right),
  })
}

///|
fn Session::capture_cell_rules(
  self : Session,
  sheet : Sheet,
  index : Int,
  selected : Range,
) -> (Array[CopiedConditional], Array[CopiedValidation]) raise @failure.Failure {
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let rules = self.conditional_rules(sheet, index, self.sheets, work)
  guard rules.reason.is_empty() else {
    @failure.reject("protected-content", rules.reason)
  }
  let tree = Tree::new(sheet.document)
  let conditional : Array[CopiedConditional] = []
  for rule in rules.rules {
    let ranges = selected.clipboard_intersections(rule.ranges)
    if ranges.is_empty() {
      continue
    }
    shift_rule_clone_guard(tree, tree.nodes[rule.container])
    conditional.push({ ranges, anchor: rule.anchor, settings: rule.settings(), })
  }
  let validations : Array[CopiedValidation] = []
  for node in validation_nodes(tree) {
    let before = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
    let ranges = selected.clipboard_intersections(before)
    if ranges.is_empty() {
      continue
    }
    shift_rule_clone_guard(tree, node)
    guard node.attribute("imeMode").unwrap_or("noControl") == "noControl" else {
      @failure.reject(
        "protected-content", "Copied validation IME settings require ownership support",
      )
    }
    validations.push({
      ranges,
      anchor: rule_anchor(before, false),
      settings: validation_settings(tree, node),
    })
  }
  (conditional, validations)
}

///|
fn CopiedCells::rule_range(
  self : CopiedCells,
  range : Range,
  target : Range,
  transpose : Bool,
) -> Range {
  if transpose {
    {
      top: target.top + range.left - self.left,
      bottom: target.top + range.right - self.left,
      left: target.left + range.top - self.top,
      right: target.left + range.bottom - self.top,
    }
  } else {
    {
      top: target.top + range.top - self.top,
      bottom: target.top + range.bottom - self.top,
      left: target.left + range.left - self.left,
      right: target.left + range.right - self.left,
    }
  }
}

///|
fn CopiedCells::rule_text(
  self : CopiedCells,
  text : String,
  anchor : Address,
  into : Address,
  target : Range,
  transpose : Bool,
  global~ : Bool = false,
) -> String raise @failure.Failure {
  if text.is_empty() {
    return text
  }
  let source : Address = if global {
    anchor
  } else if transpose {
    {
      row: self.top + into.column - target.left,
      column: self.left + into.row - target.top,
    }
  } else {
    {
      row: self.top + into.row - target.top,
      column: self.left + into.column - target.left,
    }
  }
  let prefix = if text.has_prefix("=") { "=" } else { "" }
  let expression = shift_rule_expression(text).unwrap_or_else(() => {
    @failure.reject("invalid-operation", "Copied rule formula is blank")
  })
  let adjusted = rule_expression_source(
    text,
    Some(expression),
    anchor,
    source,
    invalid=true,
  )
  let expression = shift_rule_expression(adjusted).unwrap()
  let expression = if transpose {
    expression.transpose(self.top, self.left)
  } else {
    expression
  }
  prefix +
  expression.source(
    rows=target.top - self.top,
    columns=target.left - self.left,
    invalid_ref=true,
  )
}

///|
fn CopiedCells::rules_at(
  self : CopiedCells,
  target : Range,
  transpose : Bool,
  date1904 : Bool,
) -> (Array[CopiedConditional], Array[CopiedValidation]) raise @failure.Failure {
  let conditional = self.conditional.map(rule => {
    let ranges = rule.ranges.map(r => self.rule_range(r, target, transpose))
    let anchor = rule_anchor(ranges, true)
    let text = (value : String) => {
      self.rule_text(value, rule.anchor, anchor, target, transpose)
    }
    let threshold = (value : String) => {
      self.rule_text(value, rule.anchor, anchor, target, transpose, global=true)
    }
    let settings = rule.settings
    let settings = {
      ..settings,
      formula1: text(settings.formula1),
      formula2: text(settings.formula2),
      stops: settings.stops.map(stop => {
        if stop.kind == "formula" {
          { ..stop, value: threshold(stop.value), }
        } else {
          stop
        }
      }),
      bar: settings.bar.map(bar => {
        ..bar,
        minimum: if bar.minimum.kind == "formula" {
          { ..bar.minimum, value: threshold(bar.minimum.value), }
        } else {
          bar.minimum
        },
        maximum: if bar.maximum.kind == "formula" {
          { ..bar.maximum, value: threshold(bar.maximum.value), }
        } else {
          bar.maximum
        },
      }),
      format: if transpose {
        settings.format.transposed()
      } else {
        settings.format
      },
    }
    CopiedConditional::{ ranges, anchor, settings, }
  })
  let validations = self.validations.map(rule => {
    let ranges = rule.ranges.map(r => self.rule_range(r, target, transpose))
    let anchor = rule_anchor(ranges, false)
    let text = (value : String) => {
      self.rule_text(
        if rule.settings.kind == "date" {
          copied_date_bound(value, self.date1904, date1904)
        } else {
          value
        },
        rule.anchor,
        anchor,
        target,
        transpose,
      )
    }
    CopiedValidation::{
      ranges,
      anchor,
      settings: {
        ..rule.settings,
        formula1: text(rule.settings.formula1),
        formula2: text(rule.settings.formula2),
      },
    }
  })
  (conditional, validations)
}
