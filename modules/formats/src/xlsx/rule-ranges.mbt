///|
fn Range::without(self : Range, cut : Range) -> Array[Range] {
  if !self.intersects(cut) {
    return [self]
  }
  let top = self.top.max(cut.top)
  let bottom = self.bottom.min(cut.bottom)
  let left = self.left.max(cut.left)
  let right = self.right.min(cut.right)
  let result : Array[Range] = []
  if self.top < top {
    result.push({ ..self, bottom: top - 1, })
  }
  if self.left < left {
    result.push({ top, bottom, left: self.left, right: left - 1, })
  }
  if right < self.right {
    result.push({ top, bottom, left: right + 1, right: self.right, })
  }
  if bottom < self.bottom {
    result.push({ ..self, top: bottom + 1, })
  }
  result
}

///|
fn rule_anchor(ranges : Array[Range], conditional : Bool) -> Address {
  let mut first = ranges[0]
  if conditional {
    for range in ranges {
      first = {
        ..first,
        top: first.top.min(range.top),
        left: first.left.min(range.left),
      }
    }
  }
  { row: first.top, column: first.left, }
}

///|
fn rule_formula(
  text : String,
  rows : Int,
  columns : Int,
) -> String raise @failure.Failure {
  if text.is_empty() || (rows == 0 && columns == 0) {
    return text
  }
  let prefix = if text.has_prefix("=") { "=" } else { "" }
  let source = text[prefix.length():].to_owned()
  try {
    let shifted = prefix +
      parse_formula(source).source(rows~, columns~, invalid_ref=true)
    guard shifted.length() <= 8192 else {
      @failure.reject(
        "limit-exceeded", "Shifted rule formula exceeds source budget",
      )
    }
    shifted
  } catch {
    // shortcut: Extend the shared formula grammar before shifting named or extended rule references.
    @failure.Failure(code~, ..) if code != "limit-exceeded" =>
      @failure.reject(
        "protected-content", "Rule formula requires reference-aware range editing",
      )
    error => raise error
  }
}

///|
fn clear_rule_changes(
  tree : Tree,
  node : @xml.Node,
  target : Range,
  keep_anchor~ : Bool = false,
) -> (Bool, Array[@xml.SourceChange]) raise @failure.Failure {
  let ranges = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
  if !ranges.any(range => range.intersects(target)) {
    return (false, [])
  }
  let remaining : Array[Range] = []
  for range in ranges {
    remaining.append(range.without(target))
    if keep_anchor && range.contains({ row: target.top, column: target.left, }) {
      remaining.push({
        top: target.top,
        bottom: target.top,
        left: target.left,
        right: target.left,
      })
    }
    guard remaining.length() <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Cleared rule range count exceeds budget",
      )
    }
  }
  if remaining.is_empty() {
    return (true, [])
  }
  let changes = metadata_changes(node, [
    ("sqref", remaining.map(Range::name).join(" ")),
  ])
  let conditional = node.name == "conditionalFormatting"
  let before = rule_anchor(ranges, conditional)
  let after = rule_anchor(remaining, conditional)
  let pending = tree.children.get(node.id).unwrap_or([]).copy()
  while pending.pop() is Some(child) {
    let children = tree.children.get(child.id).unwrap_or([])
    guard child.uri == spreadsheet_uri &&
      (if conditional {
        [
          "cfRule", "formula", "colorScale", "cfvo", "color", "dataBar", "iconSet",
        ].contains(child.name)
      } else {
        ["formula1", "formula2"].contains(child.name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown cell rule structure requires range editing support",
      )
    }
    if ["formula", "formula1", "formula2"].contains(child.name) {
      guard children.is_empty() else {
        @failure.reject(
          "protected-content", "Nested rule formula content is unsupported",
        )
      }
      let text = rule_formula(
        child.text,
        after.row - before.row,
        after.column - before.column,
      )
      if text != child.text {
        changes.push({
          node: child.id,
          offset: child.opening_end - child.start,
          length: child.closing_start - child.opening_end,
          xml: @xml.escape_text(text),
        })
      }
    } else if child.name == "cfvo" && child.attribute("type") == Some("formula") {
      let text = child.attribute("val").unwrap_or("")
      changes.append(
        metadata_changes(child, [
          (
            "val",
            rule_formula(
              text,
              after.row - before.row,
              after.column - before.column,
            ),
          ),
        ]),
      )
    }
    pending.append(children)
  }
  (false, changes)
}

///|
fn rule_expression(
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
        "protected-content", "Cell rule formula requires unsupported calculation or references",
      )
    error => raise error
  }
}
