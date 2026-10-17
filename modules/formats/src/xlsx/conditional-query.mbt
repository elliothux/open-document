///|
fn conditional_edit_reason(tree : Tree, node : @xml.Node) -> String {
  let source = tree.document.source()[node.start:node.end]
  if source.contains("<!--") || source.contains("<?") {
    "Retained conditional rule markup is protected"
  } else {
    ""
  }
}

///|
fn Session::conditional_query(
  self : Session,
  current : Sheet,
  conditional : ConditionalRules,
) -> Json raise @failure.Failure {
  let reason = self.dimension_reason(current)
  let reason = if reason.is_empty() { conditional.reason } else { reason }
  let tree = Tree::new(current.document)
  let rules : Array[Json] = []
  let mut units = 0
  for rule in conditional.rules {
    let ranges = rule.ranges.map(Range::name).join(" ")
    units += ranges.length() +
      rule.formulas.fold(init=0, (sum, formula) => sum + formula.length()) +
      rule.stops.fold(init=0, (sum, stop) => sum + stop.value.length())
    if rule.bar is Some(bar) {
      units += bar.minimum.value.length() + bar.maximum.value.length()
    }
    if units > 1048576 {
      return {
        "rules": [],
        "readOnlyReason": "Conditional query exceeds text budget",
      }
    }
    let reason = conditional_edit_reason(tree, tree.nodes[rule.container])
    let json : Json = {
      "priority": rule.priority,
      "ranges": ranges,
      "rule": rule.settings().json(),
      "readOnlyReason": reason,
    }
    rules.push(json)
  }
  { "rules": rules, "readOnlyReason": reason }
}
