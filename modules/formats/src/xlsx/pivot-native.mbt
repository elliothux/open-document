///|
let pivot_revision_uri = "http://schemas.microsoft.com/office/spreadsheetml/2014/revision"

///|
fn pivot_revision_attribute(
  root : @xml.Node,
  attribute : @xml.Attribute,
) -> Bool {
  if attribute.uri == pivot_revision_uri && attribute.name == "uid" {
    return attribute.value.length() == 38 &&
      attribute.value.has_prefix("{") &&
      attribute.value.has_suffix("}")
  }
  attribute.uri == "http://schemas.openxmlformats.org/markup-compatibility/2006" &&
  attribute.name == "Ignorable" &&
  root.namespaces.any(binding => {
    binding.0 == attribute.value && binding.1 == pivot_revision_uri
  })
}

///|
fn check_native_pivot_extensions(
  tree : Tree,
  root : @xml.Node,
) -> Unit raise @failure.Failure {
  guard tree.one(root.id, "extLst") is Some(list) else { return }
  conditional_node(tree, list, [], ["ext"])
  let extensions = tree.all(list.id, "ext")
  let seen : Set[String] = Set([])
  for extension in extensions {
    let id = extension.attribute("uri").unwrap_or("").to_upper()
    guard extension.attributes.length() == 1 &&
      extension.text.trim().is_empty() &&
      !seen.contains(id) &&
      tree.children.get(extension.id).unwrap_or([]) is [child] &&
      child.text.trim().is_empty() &&
      tree.children.get(child.id).unwrap_or([]).is_empty() &&
      (match (root.name, id) {
        ("pivotTableDefinition", "{962EF5D1-5CA2-4C93-8EF4-DBF5C05439D2}") =>
          child.uri == pivot_value_x14_uri &&
          child.name == "pivotTableDefinition" &&
          child.attributes.length() == 1 &&
          [Some("1"), Some("true")].contains(child.attribute("hideValuesRow"))
        ("pivotTableDefinition", "{747A6164-185A-40DC-8AA5-F01512510D54}") =>
          child.uri ==
          "http://schemas.microsoft.com/office/spreadsheetml/2016/pivotdefaultlayout" &&
          child.name == "pivotTableDefinition16" &&
          child.attributes.is_empty()
        ("pivotCacheDefinition", "{725AE2AE-9491-48BE-B2B4-4EB974FC3084}") =>
          child.uri == pivot_value_x14_uri &&
          child.name == "pivotCacheDefinition" &&
          child.attributes.is_empty()
        _ => false
      }) else {
      @failure.reject("protected-content", "Unknown native pivot extension")
    }
    seen.add(id)
  }
}

///|
fn native_pivot_default_namespace(root : @xml.Node) -> Bool {
  root.namespaces.any(binding => {
    binding.0.is_empty() && binding.1 == spreadsheet_uri
  })
}

///|
fn PivotSettings::native_single_row(self : PivotSettings) -> Bool {
  self.rows.length() == 1 &&
  self.columns.is_empty() &&
  self.values.length() == 1 &&
  self.values[0].showDataAs == "normal" &&
  self.filters.is_empty() &&
  self.subtotals.is_empty() &&
  self.dateGroups.is_empty() &&
  self.numberGroups.is_empty()
}

///|
fn retain_native_pivot_source(
  document : @xml.Document,
  generated : String,
  attributes : Array[(String, String)],
  retain : Array[String],
) -> String raise @failure.Failure {
  let root = document.nodes()[0]
  let edits = metadata_changes(root, attributes)
  let source = if edits.is_empty() {
    document
  } else {
    document.edit_source(edits).0
  }
  let root = source.nodes()[0]
  let closing = "</" + root.name + ">"
  guard generated.has_prefix("<" + root.name + " ") &&
    generated.has_suffix(closing) &&
    generated.find(">") is Some(open_end) else {
    @failure.reject(
      "invalid-operation", "Generated native pivot part has an unexpected root",
    )
  }
  let output = StringBuilder()
  output.write_string(source.source()[root.start:root.opening_end].to_owned())
  output.write_string(
    generated[open_end + 1:generated.length() - closing.length()].to_owned(),
  )
  for node in source.nodes() {
    if node.parent == root.id && retain.contains(node.name) {
      output.write_string(source.source()[node.start:node.end].to_owned())
    }
  }
  output.write_string(source.source()[root.closing_start:root.end].to_owned())
  output.to_string()
}
