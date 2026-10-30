///|
fn workbook_metadata_extension(tree : Tree, node : @xml.Node) -> Bool {
  let x15 = "http://schemas.microsoft.com/office/spreadsheetml/2010/11/main"
  let calc = "http://schemas.microsoft.com/office/spreadsheetml/2018/calcfeatures"
  guard node.uri == spreadsheet_uri &&
    node.name == "ext" &&
    node.attributes.length() == 1 &&
    node.text.trim().is_empty() &&
    tree.children.get(node.id).unwrap_or([]) is [child] else {
    return false
  }
  match node.attribute("uri").unwrap_or("").to_upper() {
    "{140A7094-0E35-4892-8432-C4D2E57EDEB5}" =>
      child.uri == x15 &&
      child.name == "workbookPr" &&
      child.attributes.all(a => {
        a.uri.is_empty() && a.name == "chartTrackingRefBase"
      }) &&
      child.text.trim().is_empty() &&
      tree.children.get(child.id).unwrap_or([]).is_empty()
    "{B58B0392-4F1F-4190-BB64-5DF3571DCE5F}" =>
      child.uri == calc &&
      child.name == "calcFeatures" &&
      child.attributes.is_empty() &&
      child.text.trim().is_empty() &&
      tree.children
      .get(child.id)
      .unwrap_or([])
      .all(feature => {
        feature.uri == calc &&
        feature.name == "feature" &&
        feature.attributes.length() == 1 &&
        feature.attribute("name") is Some(_) &&
        feature.text.trim().is_empty() &&
        tree.children.get(feature.id).unwrap_or([]).is_empty()
      })
    _ => false
  }
}

///|
fn workbook_metadata(tree : Tree, node : @xml.Node) -> Bool {
  let mc = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  let revision = "http://schemas.microsoft.com/office/spreadsheetml/2014/revision"
  if node.uri == spreadsheet_uri && node.name == "extLst" {
    return node.attributes.is_empty() &&
      node.text.trim().is_empty() &&
      tree.children
      .get(node.id)
      .unwrap_or([])
      .all(ext => workbook_metadata_extension(tree, ext))
  }
  if node.uri == revision && node.name == "revisionPtr" {
    return node.text.trim().is_empty() &&
      tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes.all(a => {
        (a.uri.is_empty() && ["revIDLastSave", "documentId"].contains(a.name)) ||
        (
          a.uri ==
          "http://schemas.microsoft.com/office/spreadsheetml/2016/revision6" &&
          ["coauthVersionLast", "coauthVersionMax"].contains(a.name)
        ) ||
        (
          a.uri ==
          "http://schemas.microsoft.com/office/spreadsheetml/2016/revision10" &&
          a.name == "uidLastSave"
        )
      })
  }
  guard node.uri == mc &&
    node.name == "AlternateContent" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    tree.children.get(node.id).unwrap_or([]) is [choice] &&
    choice.uri == mc &&
    choice.name == "Choice" &&
    choice.attributes.length() == 1 &&
    choice.attribute("Requires") is Some(_) &&
    choice.text.trim().is_empty() &&
    tree.children.get(choice.id).unwrap_or([]) is [path] else {
    return false
  }
  path.uri == "http://schemas.microsoft.com/office/spreadsheetml/2010/11/ac" &&
  path.name == "absPath" &&
  path.attributes.length() == 1 &&
  path.attribute("url") is Some(_) &&
  path.text.trim().is_empty() &&
  tree.children.get(path.id).unwrap_or([]).is_empty()
}
