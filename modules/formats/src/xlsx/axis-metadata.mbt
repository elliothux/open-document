///|
fn axis_text_change(
  tree : Tree,
  node : @xml.Node,
  text : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if text == node.text {
    return []
  }
  guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
    !tree.document.source()[node.opening_end:node.closing_start].contains("<") else {
    @failure.reject(
      "protected-content", "Opaque formula markup prevents structural editing",
    )
  }
  [
    {
      node: node.id,
      offset: node.opening_end - node.start,
      length: node.closing_start - node.opening_end,
      xml: @xml.escape_text(text),
    },
  ]
}

///|
fn AxisChange::position(self : AxisChange, address : Address) -> Address {
  self
  .address(address)
  .unwrap_or_else(() => {
    if self.rows {
      { ..address, row: self.first.min(self.limit()), }
    } else {
      { ..address, column: self.first.min(self.limit()), }
    }
  })
}

///|
fn axis_pane_name(
  pane : @xml.Node,
  change : AxisChange,
  name : String,
) -> String raise @failure.Failure {
  let count = fn(key : String, rows : Bool) -> Int raise @failure.Failure {
    let value = natural(
      pane.attribute(key).unwrap_or("0"),
      if rows {
        1048575
      } else {
        16383
      },
    )
    if rows != change.rows || value == 0 {
      value
    } else {
      change.interval(1, value).map(pair => pair.1).unwrap_or(0)
    }
  }
  let name = if count("xSplit", false) == 0 {
    match name {
      "topRight" => "topLeft"
      "bottomRight" => "bottomLeft"
      value => value
    }
  } else {
    name
  }
  if count("ySplit", true) == 0 {
    match name {
      "bottomLeft" => "topLeft"
      "bottomRight" => "topRight"
      value => value
    }
  } else {
    name
  }
}

///|
fn axis_rule_changes(
  tree : Tree,
  rule : @xml.Node,
  sheet : String,
  target : String,
  change : AxisChange,
) -> (Bool, Array[@xml.SourceChange]) raise @failure.Failure {
  let before = clear_rule_ranges(rule.attribute("sqref").unwrap_or(""))
  let after = if sheet == target {
    before.filter_map(range => change.range(range))
  } else {
    before.copy()
  }
  if after.is_empty() {
    return (true, [])
  }
  let changes = if before == after {
    []
  } else {
    metadata_changes(rule, [("sqref", after.map(Range::name).join(" "))])
  }
  let anchor = rule_anchor(before, rule.name == "conditionalFormatting")
  let mut source = rule_anchor(after, rule.name == "conditionalFormatting")
  if sheet == target {
    let value = if change.rows { source.row } else { source.column }
    let original = if change.insert {
      value -
      (if value >= change.first + change.count { change.count } else { 0 })
    } else {
      value + (if value >= change.first { change.count } else { 0 })
    }
    source = if change.rows {
      { ..source, row: original, }
    } else {
      { ..source, column: original, }
    }
  }
  let formula = fn(text : String) -> String raise @failure.Failure {
    axis_formula(
      rule_formula(text, source.row - anchor.row, source.column - anchor.column),
      Some(sheet),
      target,
      change,
    )
  }
  let pending = tree.children.get(rule.id).unwrap_or([]).copy()
  while pending.pop() is Some(node) {
    guard node.uri == spreadsheet_uri &&
      [
        "cfRule", "formula", "formula1", "formula2", "colorScale", "cfvo", "color",
        "dataBar", "iconSet",
      ].contains(node.name) else {
      @failure.reject(
        "protected-content", "Unknown rule references prevent structural editing",
      )
    }
    if ["formula", "formula1", "formula2"].contains(node.name) {
      changes.append(axis_text_change(tree, node, formula(node.text)))
    } else if node.name == "cfvo" && node.attribute("type") == Some("formula") {
      changes.append(
        metadata_changes(node, [
          ("val", formula(node.attribute("val").unwrap_or(""))),
        ]),
      )
    }
    pending.append(tree.children.get(node.id).unwrap_or([]))
  }
  (false, changes)
}

///|
fn axis_sheet_metadata(
  sheet : Sheet,
  target : String,
  change : AxisChange,
  work : RuleShiftWork,
) -> (Array[@xml.SourceChange], Bool) raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let own_sheet = sheet.name == target
  let changes : Array[@xml.SourceChange] = []
  let removed : Map[Int, Bool] = Map([])
  changes.append(sheet.axis_sparklines(change, target))
  let extra : Map[Int, Int] = Map([])
  let mut split_rules = false
  let ancestors_removed = fn(node : @xml.Node) {
    let mut parent = node.parent
    while parent >= 0 {
      if removed.contains(parent) {
        return true
      }
      parent = tree.nodes[parent].parent
    }
    false
  }
  for node in tree.document.nodes() {
    if ancestors_removed(node) {
      continue
    }
    if node.name == "dataValidations" {
      guard tree.children
        .get(node.id)
        .unwrap_or([])
        .all(child => {
          child.uri == spreadsheet_uri && child.name == "dataValidation"
        }) else {
        @failure.reject(
          "protected-content", "Unknown validation entries prevent structural editing",
        )
      }
    }
    if node.name == "conditionalFormatting" || node.name == "dataValidation" {
      if change.band is Some(_) {
        let (edits, count) = shift_rule_changes(
          tree,
          node,
          sheet.name,
          target,
          change,
          work,
        )
        changes.append(edits)
        if count == 0 {
          removed[node.id] = true
        } else if count > 1 {
          if node.name == "conditionalFormatting" {
            split_rules = true
          } else {
            extra[node.parent] = extra.get(node.parent).unwrap_or(0) + count - 1
          }
        }
      } else {
        let (remove, edits) = axis_rule_changes(
          tree,
          node,
          sheet.name,
          target,
          change,
        )
        if remove {
          removed[node.id] = true
          changes.push(sheet_node_removal(tree, node))
        } else {
          changes.append(edits)
        }
      }
    } else if node.name == "hyperlink" {
      let location = node
        .attribute("location")
        .map(text => axis_formula(text, Some(sheet.name), target, change))
      let reference = if own_sheet {
        change
        .metadata_range(Range::parse(node.attribute("ref").unwrap_or("")))
        .map(Range::name)
      } else {
        node.attribute("ref")
      }
      if reference is None || location == Some("#REF!") {
        removed[node.id] = true
        changes.push(sheet_node_removal(tree, node))
      } else {
        changes.append(metadata_changes(node, [("ref", reference.unwrap())]))
        if location is Some(text) {
          changes.append(metadata_changes(node, [("location", text)]))
        }
      }
    } else if own_sheet {
      match node.name {
        "sortState" => {
          let (edits, deleted) = axis_sort_state(tree, node, change)
          changes.append(edits)
          if deleted {
            removed[node.id] = true
          }
        }
        "mergeCell" => {
          let range = change.metadata_range(
            Range::parse(node.attribute("ref").unwrap_or("")),
          )
          if range is Some(range) &&
            (range.top != range.bottom || range.left != range.right) {
            changes.append(metadata_changes(node, [("ref", range.name())]))
          } else {
            removed[node.id] = true
            changes.push(sheet_node_removal(tree, node))
          }
        }
        "dimension" =>
          changes.append(
            metadata_changes(node, [
              (
                "ref",
                change
                .dimension_range(
                  Range::parse(node.attribute("ref").unwrap_or("A1")),
                )
                .map(Range::name)
                .unwrap_or("A1"),
              ),
            ]),
          )
        "selection" => {
          if change.band is Some(_) {
            continue
          }
          let mut active = change.position(
            Address::parse(node.attribute("activeCell").unwrap_or("A1")),
          )
          let ranges = clear_rule_ranges(
            node.attribute("sqref").unwrap_or("A1"),
          ).filter_map(range => change.range(range))
          if !ranges.is_empty() && !ranges.any(range => range.contains(active)) {
            active = { row: ranges[0].top, column: ranges[0].left, }
          }
          let values = [
            ("activeCell", active.name()),
            (
              "sqref",
              if ranges.is_empty() {
                active.name()
              } else {
                ranges.map(Range::name).join(" ")
              },
            ),
            (
              "activeCellId",
              ranges
              .search_by(range => range.contains(active))
              .unwrap_or(0)
              .to_string(),
            ),
          ]
          if node.attribute("pane") is Some(name) &&
            tree.one(node.parent, "pane") is Some(pane) {
            values.push(("pane", axis_pane_name(pane, change, name)))
          }
          changes.append(metadata_changes(node, values))
        }
        "sheetView" | "pane" => {
          if change.band is Some(_) {
            continue
          }
          if node.attribute("topLeftCell") is Some(text) {
            changes.append(
              metadata_changes(node, [
                ("topLeftCell", change.position(Address::parse(text)).name()),
              ]),
            )
          }
          if node.name == "pane" {
            let key = if change.rows { "ySplit" } else { "xSplit" }
            let value = natural(
              node.attribute(key).unwrap_or("0"),
              change.limit() - 1,
            )
            let next = if value == 0 {
              0
            } else {
              change
              .interval(1, value)
              .map(pair => pair.1)
              .unwrap_or(0)
              .min(change.limit() - 1)
            }
            changes.append(metadata_changes(node, [(key, next.to_string())]))
            changes.append(
              metadata_changes(node, [
                (
                  "activePane",
                  axis_pane_name(
                    node,
                    change,
                    node.attribute("activePane").unwrap_or("topLeft"),
                  ),
                ),
              ]),
            )
          }
        }
        _ => ()
      }
    }
  }
  for container in tree.document.nodes() {
    if ["mergeCells", "dataValidations"].contains(container.name) {
      let children = tree.children.get(container.id).unwrap_or([])
      let count = children.filter(node => !removed.contains(node.id)).length() +
        extra.get(container.id).unwrap_or(0)
      if count != children.length() {
        changes.append(
          metadata_changes(container, [("count", count.to_string())]),
        )
      }
    }
  }
  (join_insertions(changes), split_rules)
}

///|
fn Session::axis_names(
  self : Session,
  target : String,
  change : AxisChange,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  let changes : Array[@xml.SourceChange] = []
  for node in tree.document.nodes() {
    if node.name != "definedName" || node.uri != spreadsheet_uri {
      continue
    }
    let current = node
      .attribute("localSheetId")
      .map(scope => self.sheets[natural(scope, self.sheets.length() - 1)].name)
    let text = if ["_xlnm.Print_Area", "_xlnm.Print_Titles"].contains(
        node.attribute("name").unwrap_or(""),
      ) {
      let spans : Array[(Int, Int)] = []
      let tokens = formula_tokens(node.text, spans~)
      let parts : Array[String] = []
      let mut start = 0
      for index, token in tokens {
        if token is Operator(",") || token is End {
          let value = axis_formula(
            node.text[start:spans[index].0].to_owned(),
            current,
            target,
            change,
          )
          if value.trim() != "#REF!" {
            parts.push(value)
          }
          start = spans[index].1
        }
      }
      parts.join(",")
    } else {
      // A name's scope controls lookup, not its independent reference context.
      axis_formula(node.text, None, target, change)
    }
    if text.is_empty() {
      changes.push(sheet_node_removal(tree, node))
    } else {
      changes.append(axis_text_change(tree, node, text))
    }
  }
  changes
}
