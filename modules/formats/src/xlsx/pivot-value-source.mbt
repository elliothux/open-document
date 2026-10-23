///|
let pivot_value_extension = "{E15A36E0-9728-4e99-A89B-3F7291B0FE68}"

///|
let pivot_value_x14_uri = "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"

///|
fn pivot_parent_mode(mode : String) -> Bool {
  ["percentOfParentRow", "percentOfParentCol"].contains(mode)
}

///|
fn pivot_extended_mode(mode : String) -> Bool {
  pivot_parent_mode(mode) ||
  [
    "percentOfRunningTotal", "rankAscending", "rankDescending", "percentOfParent",
  ].contains(mode)
}

///|
fn pivot_read_value_mode(
  tree : Tree,
  field : @xml.Node,
) -> String raise @failure.Failure {
  conditional_node(
    tree,
    field,
    [
      "name", "fld", "subtotal", "showDataAs", "numFmtId", "baseField", "baseItem",
    ],
    ["extLst"],
  )
  let base = field.attribute("showDataAs").unwrap_or("normal")
  guard field.text.trim().is_empty() &&
    pivot_value_modes.contains(base) &&
    !pivot_extended_mode(base) else {
    @failure.reject("protected-content", "Unsupported base pivot value mode")
  }
  let mode = if tree.one(field.id, "extLst") is Some(list) {
    conditional_node(tree, list, [], ["ext"])
    guard list.text.trim().is_empty() &&
      base == "normal" &&
      tree.all(list.id, "ext") is [extension] else {
      @failure.reject("protected-content", "Conflicting pivot value extensions")
    }
    guard extension.attributes.length() == 1 &&
      extension.attribute("uri").map(value => value.to_upper()) ==
      Some(pivot_value_extension.to_upper()) &&
      extension.text.trim().is_empty() &&
      tree.children.get(extension.id).unwrap_or([]) is [value] &&
      value.uri == pivot_value_x14_uri &&
      value.name == "dataField" &&
      value.attributes.length() == 1 &&
      value.text.trim().is_empty() &&
      value.attribute("pivotShowAs") is Some(mode) &&
      pivot_extended_mode(mode) &&
      tree.children.get(value.id).unwrap_or([]).is_empty() else {
      @failure.reject("protected-content", "Unsupported pivot value extension")
    }
    mode
  } else {
    base
  }
  guard pivot_base_mode(mode) == (field.attribute("baseField") is Some(_)) else {
    @failure.reject(
      "protected-content", "Pivot base field disagrees with value mode",
    )
  }
  guard pivot_compare_mode(mode) == (field.attribute("baseItem") is Some(_)) else {
    @failure.reject(
      "protected-content", "Pivot base item disagrees with value mode",
    )
  }
  guard field
    .attribute("numFmtId")
    .map(id => id == (if pivot_percent(mode) { "10" } else { "0" }))
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Unsupported pivot value number format",
    )
  }
  mode
}

///|
fn PivotCache::value_markup(
  self : PivotCache,
  value : PivotValue,
) -> String raise @failure.Failure {
  let base = value.baseField
    .map(field => " baseField=\"\{field}\"")
    .unwrap_or("")
  let attributes = "name=\"\{escaped_attribute(encoded_text(value.name))}\" fld=\"\{value.field}\" subtotal=\"\{value.aggregate}\"\{base}\{self.base_item_markup(value)}"
  if pivot_extended_mode(value.showDataAs) {
    "<dataField \{attributes} numFmtId=\"\{if pivot_percent(value.showDataAs) {10} else {0}}\"><extLst><ext uri=\"\{pivot_value_extension}\"><x14:dataField xmlns:x14=\"\{pivot_value_x14_uri}\" pivotShowAs=\"\{value.showDataAs}\"/></ext></extLst></dataField>"
  } else {
    let mode = if value.showDataAs == "normal" {
      ""
    } else {
      " showDataAs=\"\{value.showDataAs}\" numFmtId=\"\{if pivot_percent(value.showDataAs) {10} else {0}}\""
    }
    "<dataField \{attributes}\{mode}/>"
  }
}
