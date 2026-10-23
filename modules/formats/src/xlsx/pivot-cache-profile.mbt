///|
fn pivot_cache_profile(
  cache : @xml.Document,
  records : String,
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
  for node in cache.nodes() {
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
        "worksheetSource" => ["ref", "sheet"]
        "cacheFields" => ["count"]
        "cacheField" => ["name", "databaseField"]
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
          ]
        "n" | "s" | "b" | "e" | "d" => ["v"]
        _ => []
      }
      conditional_node(cache_tree, node, attributes, children)
    }
  }
  guard cache_root.attributes.all(attribute => {
      (
        attribute.uri ==
        relationship_uri[:relationship_uri.length() - 1].to_owned() &&
        attribute.name == "id"
      ) ||
      (
        attribute.uri.is_empty() &&
        [
          "recordCount", "saveData", "refreshOnLoad", "enableRefresh", "invalid",
          "createdVersion", "refreshedVersion", "minRefreshableVersion",
        ].contains(attribute.name)
      )
    }) &&
    cache_tree.children
    .get(cache_root.id)
    .unwrap_or([])
    .all(node => {
      node.uri == spreadsheet_uri &&
      ["cacheSource", "cacheFields"].contains(node.name)
    }) &&
    flag(cache_root, "enableRefresh", fallback=true) &&
    flag(cache_root, "saveData", fallback=true) else {
    @failure.reject(
      "protected-content", "Extended pivot cache metadata requires support",
    )
  }
}
