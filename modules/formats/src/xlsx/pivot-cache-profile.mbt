///|
fn pivot_cache_profile(
  cache : @xml.Document,
  records : String,
  native~ : Bool = false,
) -> Unit raise @failure.Failure {
  pivot_plain_source(cache)
  let cache_tree = Tree::new(cache)
  let cache_root = cache_tree.root("pivotCacheDefinition")
  guard cache_root.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    ) ==
    Some(records) else {
    @failure.reject(
      "malformed-xlsx", "Pivot record relationship disagrees with cache",
    )
  }
  let extensions = if native {
    cache_tree.one(cache_root.id, "extLst")
  } else {
    None
  }
  for node in cache.nodes() {
    if extensions is Some(list) &&
      node.start >= list.start &&
      node.end <= list.end {
      continue
    }
    let children = match node.name {
      "pivotCacheDefinition" => ["cacheSource", "cacheFields"]
      "cacheSource" => ["worksheetSource"]
      "cacheFields" => ["cacheField"]
      "cacheField" => ["sharedItems", "fieldGroup"]
      "fieldGroup" => ["rangePr", "groupItems"]
      "groupItems" => ["s"]
      "sharedItems" => ["n", "s", "b", "e", "m", "d"]
      _ => []
    }
    if node.id != 0 {
      let attributes = match node.name {
        "cacheSource" => ["type"]
        "worksheetSource" => ["ref", "sheet", "name"]
        "cacheFields" => ["count"]
        "cacheField" =>
          ["name", "databaseField"] + (if native { ["numFmtId"] } else { [] })
        "fieldGroup" => ["base", "par"]
        "rangePr" =>
          [
            "autoStart", "autoEnd", "groupBy", "startNum", "endNum", "groupInterval",
            "startDate", "endDate",
          ]
        "groupItems" => ["count"]
        "sharedItems" =>
          [
            "count", "containsNumber", "containsString", "containsBlank", "containsNonDate",
            "containsDate", "containsSemiMixedTypes", "containsMixedTypes", "containsInteger",
            "longText",
          ] +
          (if native { ["minValue", "maxValue"] } else { [] })
        "n" | "s" | "b" | "e" | "d" => ["v"]
        _ => []
      }
      conditional_node(cache_tree, node, attributes, children)
      if native && node.name == "cacheField" {
        guard [None, Some("0")].contains(node.attribute("numFmtId")) else {
          @failure.reject(
            "protected-content", "Native pivot cache field number format requires support",
          )
        }
      }
    }
  }
  guard cache_root.attributes.all(attribute => {
      (
        attribute.uri ==
        relationship_uri[:relationship_uri.length() - 1].to_owned() &&
        attribute.name == "id"
      ) ||
      (native && pivot_revision_attribute(cache_root, attribute)) ||
      (
        attribute.uri.is_empty() &&
        [
          "recordCount", "saveData", "refreshOnLoad", "enableRefresh", "invalid",
          "createdVersion", "refreshedVersion", "minRefreshableVersion",
        ].contains(attribute.name)
      ) ||
      (
        native &&
        attribute.uri.is_empty() &&
        ["refreshedBy", "refreshedDate"].contains(attribute.name)
      )
    }) &&
    cache_tree.children
    .get(cache_root.id)
    .unwrap_or([])
    .all(node => {
      node.uri == spreadsheet_uri &&
      (
        ["cacheSource", "cacheFields"].contains(node.name) ||
        (native && node.name == "extLst")
      )
    }) &&
    flag(cache_root, "enableRefresh", fallback=true) &&
    flag(cache_root, "saveData", fallback=true) else {
    @failure.reject(
      "protected-content", "Extended pivot cache metadata requires support",
    )
  }
  if native {
    guard native_pivot_default_namespace(cache_root) else {
      @failure.reject(
        "protected-content", "Native pivot cache requires a default namespace",
      )
    }
    check_native_pivot_extensions(cache_tree, cache_root)
  }
}
