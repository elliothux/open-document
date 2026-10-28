///|
fn validation_nodes(tree : Tree) -> Array[@xml.Node] raise @failure.Failure {
  for node in tree.document.nodes() {
    guard !(["dataValidation", "dataValidations"].contains(node.name) &&
      node.uri != spreadsheet_uri) else {
      @failure.reject(
        "protected-content", "Extended data validation requires editing support",
      )
    }
  }
  guard tree.one(tree.root("worksheet").id, "dataValidations")
    is Some(container) else {
    return []
  }
  guard container.attributes.all(a => {
    a.uri.is_empty() &&
    ["count", "disablePrompts", "xWindow", "yWindow"].contains(a.name)
  }) else {
    @failure.reject(
      "protected-content", "Unknown data validation container properties",
    )
  }
  let children = tree.children.get(container.id).unwrap_or([])
  guard children.length() <= 4096 &&
    children.all(n => n.uri == spreadsheet_uri && n.name == "dataValidation") else {
    @failure.reject(
      "protected-content", "Unknown or excessive data validations",
    )
  }
  children
}

///|
fn Sheet::validation_at(
  sheet : Sheet,
  target : Range,
) -> (DataValidation?, Bool) raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let nodes = validation_nodes(tree)
  let anchor : Address = { row: target.top, column: target.left, }
  let mut selected : DataValidation? = None
  for node in nodes {
    let ranges = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
    if ranges.any(r => r.contains(anchor)) {
      selected = Some(
        validation_settings(tree, node).at(rule_anchor(ranges, false), anchor),
      )
      break
    }
  }
  let mut remaining = [target]
  let mut mixed = false
  let mut work = 1048576
  for node in nodes {
    let ranges = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
    let mut settings : DataValidation? = None
    for range in ranges {
      let next = []
      for piece in remaining {
        work -= 1
        guard work >= 0 else {
          @failure.reject(
            "limit-exceeded", "Validation query exceeds range work budget",
          )
        }
        if piece.intersects(range) {
          if settings is None {
            settings = Some(
              validation_settings(tree, node).at(
                rule_anchor(ranges, false),
                anchor,
              ),
            )
          }
          if settings != selected {
            mixed = true
          }
        }
        next.append(piece.without(range))
        guard next.length() <= 4096 else {
          @failure.reject(
            "limit-exceeded", "Validation query fragments exceed budget",
          )
        }
      }
      remaining = next
    }
    if remaining.is_empty() {
      break
    }
  }
  if !remaining.is_empty() && selected is Some(_) {
    mixed = true
  }
  (selected, mixed)
}

///|
fn Session::validation_reason(
  self : Session,
  sheet : Sheet,
  target : Range,
) -> String {
  let reason = self.dimension_reason(sheet)
  if !reason.is_empty() {
    return reason
  }
  try {
    let tree = Tree::new(sheet.document)
    let nodes = validation_nodes(tree)
    if tree.one(tree.root("worksheet").id, "dataValidations") is Some(container) {
      let source = tree.document.source()[container.start:container.end]
      if source.contains("<!--") || source.contains("<?") {
        return "Retained data validation markup is protected"
      }
    }
    for node in nodes {
      let ranges = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
      if ranges.any(r => r.intersects(target)) {
        let settings = validation_settings(tree, node)
        settings.check_metadata()
        if !["noControl", ""].contains(node.attribute("imeMode").unwrap_or("")) {
          return "Validation input method settings are protected"
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::validation_query(
  self : Session,
  sheet : Int32,
  target : Range,
) -> Json {
  let current = self.sheets[sheet]
  let reason = self.validation_reason(current, target)
  let (rule, mixed, reason) = try {
    let (rule, mixed) = current.validation_at(target)
    if rule is Some(rule) {
      rule.check_metadata()
    }
    (rule, mixed, reason)
  } catch {
    @failure.Failure(message~, ..) => (None, true, message)
  }
  let (options, options_reason) = if rule is Some(rule) &&
    rule.kind == "list" &&
    !mixed {
    (self.validation_options(sheet, target, rule).map(Value::display), "") catch {
      @failure.Failure(message~, ..) => ([], message)
    }
  } else {
    ([], "")
  }
  let prompt_visible = rule.map(r => r.showInputMessage).unwrap_or(false) &&
    (try {
      let tree = Tree::new(current.document)
      !tree
      .one(tree.root("worksheet").id, "dataValidations")
      .map(n => flag(n, "disablePrompts"))
      .unwrap_or(false)
    } catch {
      @failure.Failure(..) => false
    })
  {
    "rule": rule.map(DataValidation::to_json).unwrap_or(Json::null()),
    "mixed": mixed,
    "readOnlyReason": reason,
    "options": options,
    "optionsReason": options_reason,
    "promptVisible": prompt_visible,
  }
}
