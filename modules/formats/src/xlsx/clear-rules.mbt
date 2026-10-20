///|
fn clear_rule_ranges(source : String) -> Array[Range] raise @failure.Failure {
  let values = source
    .replace_all(old="\t", new=" ")
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .split(" ")
    .filter(value => !value.is_empty())
    .to_array()
  guard !values.is_empty() && values.length() <= 4096 else {
    @failure.reject("protected-content", "Invalid cell rule ranges")
  }
  let ranges : Array[Range] = []
  for value in values {
    ranges.push(Range::parse(value.to_owned()))
  }
  ranges
}

///|
fn Range::covers(self : Range, other : Range) -> Bool {
  self.top <= other.top &&
  self.left <= other.left &&
  self.bottom >= other.bottom &&
  self.right >= other.right
}

///|
fn clear_rule_selected(
  node : @xml.Node,
  target : Range,
  attribute : String,
) -> Bool raise @failure.Failure {
  let ranges = clear_rule_ranges(node.attribute(attribute).unwrap_or(""))
  if !ranges.any(range => range.intersects(target)) {
    return false
  }
  guard ranges.all(range => target.covers(range)) else {
    @failure.reject(
      "protected-content", "Partially covered cell rules require range splitting",
    )
  }
  true
}

///|
fn clear_rules(
  document : @xml.Document,
  target : Range,
  all : Bool,
  table_parts~ : Bool = false,
  sparklines~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let changes : Array[@xml.SourceChange] = []
  for node in tree.children.get(root.id).unwrap_or([]) {
    guard node.uri == spreadsheet_uri else {
      @failure.reject(
        "protected-content", "Unknown worksheet namespace requires clearing support",
      )
    }
    if sparklines && sparkline_extension(tree, node) {
      continue
    }
    if (
        ["extLst", "pivotTableParts"].contains(node.name) ||
        (node.name == "tableParts" && !table_parts)
      ) &&
      !tree.children.get(node.id).unwrap_or([]).is_empty() {
      @failure.reject(
        "protected-content", "Cell-bound table or extension resources require clearing support",
      )
    }
    if node.name == "conditionalFormatting" {
      let (remove, edits) = clear_rule_changes(tree, node, target)
      if remove {
        changes.push(sheet_node_removal(tree, node))
      } else {
        changes.append(edits)
      }
    }
    if node.name == "mergeCells" ||
      (all && ["hyperlinks", "dataValidations"].contains(node.name)) {
      let name = match node.name {
        "mergeCells" => "mergeCell"
        "hyperlinks" => "hyperlink"
        _ => "dataValidation"
      }
      let children = tree.all(node.id, name)
      let removed : Array[@xml.Node] = []
      let edits : Array[@xml.SourceChange] = []
      for child in children {
        if name == "dataValidation" {
          let (remove, updates) = clear_rule_changes(tree, child, target)
          if remove {
            removed.push(child)
          } else {
            edits.append(updates)
          }
        } else if name == "hyperlink" {
          if target.covers(Range::parse(child.attribute("ref").unwrap_or(""))) {
            removed.push(child)
          }
        } else if clear_rule_selected(child, target, "ref") {
          removed.push(child)
        }
      }
      if removed.is_empty() && edits.is_empty() {
        continue
      }
      guard children.length() ==
        tree.children.get(node.id).unwrap_or([]).length() else {
        @failure.reject(
          "protected-content", "Unknown cell rule children require clearing support",
        )
      }
      if removed.length() == children.length() {
        changes.push(sheet_node_removal(tree, node))
      } else {
        changes.append(edits)
        for child in removed {
          changes.push(sheet_node_removal(tree, child))
        }
        if node.attribute("count") is Some(_) {
          changes.append(
            metadata_changes(node, [
              ("count", (children.length() - removed.length()).to_string()),
            ]),
          )
        }
      }
    }
  }
  changes
}
