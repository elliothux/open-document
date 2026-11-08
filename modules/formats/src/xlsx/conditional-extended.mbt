///|
let conditional_extension_uri = "{78C0D931-6437-407D-A8EE-F0AAD7539E65}"

///|
fn conditional_containers(
  tree : Tree,
  work : FormulaWork,
) -> Array[@xml.Node] raise @failure.Failure {
  let root = tree.sheet_root()
  let containers = tree.all(root.id, "conditionalFormatting")
  if tree.one(root.id, "extLst") is Some(list) {
    for extension in tree.children.get(list.id).unwrap_or([]) {
      if extension.attribute("uri").unwrap_or("").to_upper() !=
        conditional_extension_uri {
        continue
      }
      let groups = tree.children.get(extension.id).unwrap_or([])
      guard extension.uri == spreadsheet_uri &&
        extension.name == "ext" &&
        extension.text.trim().is_empty() &&
        extension.attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
        groups.length() == 1 &&
        groups[0].uri == sparkline_uri &&
        groups[0].name == "conditionalFormattings" &&
        groups[0].attributes.is_empty() &&
        groups[0].text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Unsupported conditional formatting extension",
        )
      }
      for container in tree.children.get(groups[0].id).unwrap_or([]) {
        work.spend()
        guard containers.length() < 4096 &&
          container.uri == sparkline_uri &&
          container.name == "conditionalFormatting" &&
          container.text.trim().is_empty() &&
          container.attributes.all(a => a.uri.is_empty() && a.name == "pivot") &&
          !flag(container, "pivot") else {
          @failure.reject(
            "protected-content", "Unsupported extended conditional container",
          )
        }
        let children = tree.children.get(container.id).unwrap_or([])
        work.spend(amount=children.length())
        let ranges = children.filter(n => {
          n.uri == sparkline_formula_uri && n.name == "sqref"
        })
        guard ranges.length() == 1 &&
          ranges[0].attributes.is_empty() &&
          tree.children.get(ranges[0].id).unwrap_or([]).is_empty() &&
          children.all(n => {
            (n.uri == sparkline_uri && n.name == "cfRule") ||
            (n.uri == sparkline_formula_uri && n.name == "sqref")
          }) else {
          @failure.reject(
            "protected-content", "Invalid extended conditional ranges",
          )
        }
        containers.push(container)
      }
    }
  }
  let accepted = Set::from_array(containers.map(n => n.id))
  for node in tree.document.nodes() {
    guard node.name != "conditionalFormatting" || accepted.contains(node.id) else {
      @failure.reject(
        "protected-content", "Extended conditional formatting is unsupported",
      )
    }
  }
  containers
}

///|
fn extended_conditional_rule(
  tree : Tree,
  node : @xml.Node,
) -> Unit raise @failure.Failure {
  guard node.uri == sparkline_uri &&
    node.text.trim().is_empty() &&
    ["cellIs", "expression"].contains(node.attribute("type").unwrap_or("")) &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      ["type", "operator", "priority", "stopIfTrue", "id"].contains(a.name)
    }) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => {
      (n.uri == sparkline_formula_uri && n.name == "f") ||
      (n.uri == sparkline_uri && n.name == "dxf")
    }) else {
    @failure.reject(
      "protected-content", "Unsupported extended conditional rule",
    )
  }
}

///|
fn ConditionalRules::renders(
  self : ConditionalRules,
  diagnostic : String,
  sheet : Sheet,
) -> Bool raise @failure.Failure {
  if self.table_styles.renders(diagnostic, sheet.id) {
    return true
  }
  if !self.reason.is_empty() ||
    !diagnostic.has_suffix("extLst") ||
    !diagnostic.has_prefix("unrendered:" + sheet.id + ":") {
    return false
  }
  let tree = Tree::new(sheet.document)
  guard tree.one(tree.sheet_root().id, "extLst") is Some(list) &&
    diagnostic == "unrendered:" + sheet.id + ":" + list.qualified &&
    list.attributes.is_empty() else {
    return false
  }
  let extensions = tree.children.get(list.id).unwrap_or([])
  !extensions.is_empty() &&
  extensions.all(n => {
    n.uri == spreadsheet_uri &&
    n.name == "ext" &&
    n.attribute("uri").unwrap_or("").to_upper() == conditional_extension_uri
  })
}
