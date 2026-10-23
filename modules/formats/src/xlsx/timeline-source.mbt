///|
let timeline_uri = "http://schemas.microsoft.com/office/spreadsheetml/2010/11/main"

///|
let timeline_relationship_uri = "http://schemas.microsoft.com/office/2010/relationships/"

///|
let timeline_view_extension = "{7E03D99C-DC04-49D9-9315-930204A7B6E9}"

///|
let timeline_cache_extension = "{D0CA8CA8-9F24-4464-BF8E-62219DCF47F9}"

///|
fn Tree::timeline_children(
  self : Tree,
  parent : Int,
  name : String,
) -> Array[@xml.Node] {
  self.children
  .get(parent)
  .unwrap_or([])
  .filter(node => node.uri == timeline_uri && node.name == name)
}

///|
fn Tree::timeline_node(
  self : Tree,
  parent : Int,
  name : String,
) -> @xml.Node raise @failure.Failure {
  guard self.timeline_children(parent, name) is [node] else {
    @failure.reject(
      "protected-content",
      "Missing or duplicate timeline " + name,
    )
  }
  node
}

///|
fn timeline_profile(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == timeline_uri &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      (a.uri.is_empty() && attributes.contains(a.name)) ||
      (
        a.uri ==
        "http://schemas.microsoft.com/office/spreadsheetml/2016/revision10" &&
        a.name == "uid"
      ) ||
      (a.uri == drawing_compatibility_uri && a.name == "Ignorable")
    }) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(child => child.uri == timeline_uri && children.contains(child.name)) else {
    @failure.reject("protected-content", "Unsupported timeline metadata")
  }
}

///|
fn Session::timeline_parts(
  self : Session,
  owner : String,
  document : @xml.Document,
  extension : String,
  container : String,
  child : String,
  kind : String,
) -> Array[String] raise @failure.Failure {
  let tree = Tree::new(document)
  let matches = tree
    .one(0, "extLst")
    .map(list => {
      tree
      .all(list.id, "ext")
      .filter(ext => {
        ext
        .attribute("uri")
        .map(uri => uri.to_upper() == extension)
        .unwrap_or(false)
      })
    })
    .unwrap_or([])
  guard matches.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate timeline extension")
  }
  guard matches is [ext] else { return [] }
  guard ext.attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
    ext.text.trim().is_empty() &&
    tree.children.get(ext.id).unwrap_or([]).length() == 1 else {
    @failure.reject("protected-content", "Unsupported timeline extension")
  }
  let list = tree.timeline_node(ext.id, container)
  timeline_profile(tree, list, [], [child])
  let entries = tree.timeline_children(list.id, child)
  guard !entries.is_empty() && entries.length() <= 64 else {
    @failure.reject("limit-exceeded", "Timeline references exceed budget")
  }
  let seen : Map[String, Bool] = Map([])
  entries.map(node => {
    guard node.attributes.length() == 1 &&
      node.text.trim().is_empty() &&
      tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      is Some(id) &&
      self.relationships().filter(link => link.owner == owner && link.id == id)
      is [link] &&
      !link.external &&
      link.kind == timeline_relationship_uri + kind else {
      @failure.reject(
        "protected-content", "Invalid or external timeline relationship",
      )
    }
    guard !seen.contains(link.target.to_lower()) &&
      self
      .part_xml("[Content_Types].xml")
      .nodes()
      .filter(entry => {
        entry.name == "Override" &&
        entry.uri ==
        "http://schemas.openxmlformats.org/package/2006/content-types" &&
        entry
        .attribute("PartName")
        .map(path => path.to_lower() == "/" + link.target.to_lower())
        .unwrap_or(false)
      })
      is [content] &&
      content.attribute("ContentType") ==
      Some("application/vnd.ms-excel." + kind + "+xml") else {
      @failure.reject(
        "protected-content", "Timeline reference or content type is ambiguous",
      )
    }
    guard !self.relationships().any(other => other.owner == link.target) else {
      @failure.reject(
        "protected-content", "Timeline part relationships require support",
      )
    }
    seen[link.target.to_lower()] = true
    link.target
  })
}

///|
fn timeline_range(
  tree : Tree,
  node : @xml.Node,
) -> TimelineRange raise @failure.Failure {
  timeline_profile(tree, node, ["startDate", "endDate"], [])
  let start = node.attribute("startDate").unwrap_or("")
  let end = node.attribute("endDate").unwrap_or("")
  guard pivot_date_parse(start, false) <= pivot_date_parse(end, false) else {
    @failure.reject("protected-content", "Timeline dates are reversed")
  }
  { start, end, }
}

///|
// Native timeline data caches and result caches have separate identities.
fn Session::timeline_pivot_cache(
  self : Session,
  id : String,
) -> String raise @failure.Failure {
  let id = natural(id, 2147483647)
  let tree = Tree::new(self.workbook)
  let entries = tree
    .one(0, "pivotCaches")
    .map(list => tree.all(list.id, "pivotCache"))
    .unwrap_or([])
  for
    list in tree.document
    .nodes()
    .filter(node => {
      node.uri == timeline_uri && node.name == "timelineCachePivotCaches"
    }) {
    let parent = tree.nodes[list.parent]
    guard parent.uri == spreadsheet_uri &&
      parent.name == "ext" &&
      parent
      .attribute("uri")
      .map(uri => uri.to_upper() == "{A2CB5862-8E78-49C6-8D9D-AF26E26ADB89}")
      .unwrap_or(false) &&
      tree.nodes[parent.parent].name == "extLst" &&
      tree.nodes[tree.nodes[parent.parent].parent].id == 0 else {
      @failure.reject(
        "protected-content", "Timeline cache directory is misplaced",
      )
    }
    guard tree.children
      .get(list.id)
      .unwrap_or([])
      .all(node => node.uri == spreadsheet_uri && node.name == "pivotCache") else {
      @failure.reject(
        "protected-content", "Unknown timeline data cache reference",
      )
    }
    entries.append(tree.all(list.id, "pivotCache"))
  }
  guard entries.filter(entry => {
      entry
      .attribute("cacheId")
      .map(value => natural(value, 2147483647) == id)
      .unwrap_or(false)
    })
    is [entry] &&
    entry.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    )
    is Some(relation) &&
    self
    .relationships()
    .filter(link => link.owner == self.main && link.id == relation)
    is [link] &&
    !link.external &&
    link.kind == relationship_uri + "pivotCacheDefinition" else {
    @failure.reject(
      "protected-content", "Timeline data cache identity is unavailable",
    )
  }
  guard self
    .part_xml("[Content_Types].xml")
    .nodes()
    .filter(node => {
      node.name == "Override" &&
      node
      .attribute("PartName")
      .map(path => path.to_lower() == "/" + link.target.to_lower())
      .unwrap_or(false)
    })
    is [content] &&
    content.attribute("ContentType") ==
    Some(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml",
    ) else {
    @failure.reject(
      "protected-content", "Timeline data cache content type is invalid",
    )
  }
  link.target
}
