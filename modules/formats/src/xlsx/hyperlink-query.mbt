///|
fn check_hyperlink_target(target : String) -> Unit raise @failure.Failure {
  guard !target.is_empty() &&
    target.length() <= 2048 &&
    @xml.valid_text(target) &&
    target.iter().all(c => c.to_int() > 31 && c.to_int() != 127 && c != '\\') else {
    @failure.reject(
      "invalid-operation", "Invalid or excessive hyperlink target",
    )
  }
  if target.has_prefix("#") {
    guard target.length() > 1 else {
      @failure.reject(
        "invalid-operation", "Internal hyperlink requires a range or defined name",
      )
    }
    ignore(parse_formula(target[1:].to_owned()))
  } else {
    let lower = target.to_lower()
    let prefix = if lower.has_prefix("https://") {
      8
    } else if lower.has_prefix("http://") || lower.has_prefix("mailto:") {
      7
    } else {
      0
    }
    guard prefix > 0 &&
      target.length() > prefix &&
      target.iter().all(c => !c.is_whitespace()) else {
      @failure.reject(
        "invalid-operation", "Hyperlink requires HTTP, HTTPS, mailto or an internal #range",
      )
    }
  }
}

///|
fn hyperlink_nodes(tree : Tree) -> Array[@xml.Node] raise @failure.Failure {
  for n in tree.document.nodes() {
    guard !["hyperlinks", "hyperlink"].contains(n.name) ||
      n.uri == spreadsheet_uri else {
      @failure.reject(
        "protected-content", "Extended hyperlinks require editing support",
      )
    }
  }
  guard tree.one(tree.root("worksheet").id, "hyperlinks") is Some(container) else {
    return []
  }
  let nodes = tree.children.get(container.id).unwrap_or([])
  guard container.attributes.is_empty() &&
    container.text.trim().is_empty() &&
    nodes.length() <= 4096 &&
    nodes.all(n => n.uri == spreadsheet_uri && n.name == "hyperlink") else {
    @failure.reject(
      "protected-content", "Unknown or excessive hyperlink container",
    )
  }
  nodes
}

///|
fn hyperlink_source(
  tree : Tree,
  node : @xml.Node,
) -> Unit raise @failure.Failure {
  let rel = relationship_uri[:relationship_uri.length() - 1].to_owned()
  guard node.attributes.all(a => {
      (
        a.uri.is_empty() &&
        ["ref", "location", "display", "tooltip"].contains(a.name)
      ) ||
      (a.uri == rel && a.name == "id")
    }) &&
    tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.text.trim().is_empty() &&
    !(node.attribute("location") is Some(_) &&
    node.attribute("id", uri=rel) is Some(_)) else {
    @failure.reject(
      "protected-content", "Unknown or combined hyperlink metadata requires editing support",
    )
  }
  let source = tree.document.source()[node.start:node.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Retained hyperlink source is protected",
    )
  }
}

///|
fn hyperlink_target(
  tree : Tree,
  node : @xml.Node,
  links : Map[String, @opc.Relationship],
) -> String raise @failure.Failure {
  hyperlink_source(tree, node)
  let rel = relationship_uri[:relationship_uri.length() - 1].to_owned()
  let target = if node.attribute("location") is Some(location) {
    "#" + location
  } else {
    guard node.attribute("id", uri=rel).bind(id => links.get(id)) is Some(link) &&
      link.external &&
      link.kind == relationship_uri + "hyperlink" else {
      @failure.reject(
        "protected-content", "Unresolved or unsupported hyperlink relationship",
      )
    }
    guard !link.target.has_prefix("#") else {
      @failure.reject(
        "protected-content", "External fragment-only hyperlink relationships require editing support",
      )
    }
    link.target
  }
  check_hyperlink_target(target)
  target
}

///|
fn Session::hyperlink_relations(
  self : Session,
  sheet : String,
) -> Map[String, @opc.Relationship] raise @failure.Failure {
  Map::from_array(
    self
    .relationships()
    .iter()
    .filter(r => r.owner == sheet)
    .map(r => (r.id, r))
    .to_array(),
  )
}

///|
fn Session::hyperlink_at(
  self : Session,
  sheet : Sheet,
  target : Range,
) -> (String?, Bool) raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let links = self.hyperlink_relations(sheet.id)
  let nodes = hyperlink_nodes(tree)
  let anchor : Address = { row: target.top, column: target.left, }
  let mut value : String? = None
  let mut picked : Array[(Range, String)] = []
  for node in nodes {
    let range = Range::parse(node.attribute("ref").unwrap_or(""))
    if !range.intersects(target) {
      continue
    }
    guard !picked.any(p => p.0.intersects(range)) else {
      @failure.reject(
        "protected-content", "Overlapping hyperlinks require ownership support",
      )
    }
    let text = hyperlink_target(tree, node, links)
    picked.push((range, text))
  }
  picked = self.with_formula_hyperlinks(sheet, picked, target~)
  for (range, text) in picked {
    if range.contains(anchor) {
      value = Some(text)
    }
  }
  let mut remaining = [target]
  let mut mixed = false
  let mut work = 1048576
  for (range, text) in picked {
    if Some(text) != value {
      mixed = true
    }
    let next : Array[Range] = []
    for piece in remaining {
      work -= 1
      guard work >= 0 else {
        @failure.reject("limit-exceeded", "Hyperlink query work exceeds budget")
      }
      next.append(piece.without(range))
      guard next.length() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Hyperlink query fragments exceed budget",
        )
      }
    }
    remaining = next
  }
  if value is Some(_) && !remaining.is_empty() {
    mixed = true
  }
  (if mixed { None } else { value }, mixed)
}

///|
fn Session::hyperlink_destination(
  self : Session,
  sheet : Int32,
  origin : Address,
  target : String,
  work? : FormulaWork,
) -> (String, Range) raise @failure.Failure {
  check_hyperlink_target(target)
  guard target.has_prefix("#") else {
    @failure.reject(
      "invalid-operation", "External hyperlinks require an explicit platform open",
    )
  }
  let work = work.unwrap_or_else(() => {
    remaining: 1048576,
    date1904: self.date1904,
    origin,
    names: self.formula_names(),
  })
  work.spend(amount=target.length())
  work.origin = origin
  let expression = parse_formula(target[1:].to_owned()).resolve_names(
    self.sheets,
    sheet,
    origin,
    work,
  )
  guard expression is Reference(name, first, last) else {
    @failure.reject(
      "invalid-operation", "Internal hyperlink must resolve to one rectangle",
    )
  }
  let index = referenced_sheet(self.sheets, sheet, name)
  guard self.sheets[index].state == "visible" else {
    @failure.reject("protected-content", "Hyperlink target worksheet is hidden")
  }
  (self.sheets[index].id, first.range(last.unwrap_or(first)))
}

///|
fn Session::hyperlink_reason(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> String {
  let reason = self.dimension_reason(sheet)
  if !reason.is_empty() {
    return reason
  }
  if sheet.merges.any(m => m.intersects(range) && !range.covers(m)) {
    return "Hyperlink range must contain each intersected merged cell"
  }
  if self.formula_hyperlink_owner(sheet, range) {
    return "Edit HYPERLINK through the cell formula"
  }
  ""
}

///|
fn hyperlink_name_reference(
  text : String,
  sheets : Array[Sheet],
  context : Int32,
  origin : Address,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  try {
    check_hyperlink_target("#" + text)
    work.spend(amount=text.length())
    parse_formula(text).resolve_names(sheets, context, origin, work)
    is Reference(_, _, _)
  } catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(..) => false
  }
}

///|
fn deleted_name_hyperlinks(
  tree : Tree,
  sheets : Array[Sheet],
  context : Int32,
  before : FormulaWork,
  after : FormulaWork,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  for node in hyperlink_nodes(tree) {
    if node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      is Some(_) {
      continue
    }
    if node.attribute("location") is Some(text) {
      let range = Range::parse(node.attribute("ref").unwrap_or(""))
      let origin : Address = { row: range.top, column: range.left, }
      if hyperlink_name_reference(text, sheets, context, origin, before) &&
        !hyperlink_name_reference(text, sheets, context, origin, after) {
        hyperlink_source(tree, node)
        changes.push(sheet_node_removal(tree, node))
      }
    }
  }
  changes
}

///|
fn Session::hyperlink_query(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> Json {
  let (target, mixed, reason) = try {
    let (target, mixed) = self.hyperlink_at(sheet, range)
    (target, mixed, self.hyperlink_reason(sheet, range))
  } catch {
    @failure.Failure(message~, ..) => (None, true, message)
  }
  let navigation_reason = if target is Some(text) && text.has_prefix("#") {
    try {
      ignore(
        self.hyperlink_destination(
          self.sheet_index(sheet.id),
          { row: range.top, column: range.left, },
          text,
        ),
      )
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
  } else {
    ""
  }
  {
    "target": target.map(t => Json(t)).unwrap_or(Json::null()),
    "mixed": mixed,
    "readOnlyReason": reason,
    "navigationReason": navigation_reason,
  }
}
