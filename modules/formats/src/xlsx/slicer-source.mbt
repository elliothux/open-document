///|
let slicer_uri = "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"

///|
let slicer_relationship_uri = "http://schemas.microsoft.com/office/2007/relationships/"

///|
let slicer_cache_extension = "{BBE1A952-AA13-448E-AADC-164F8A28A991}"

///|
let slicer_list_extension = "{A8765BA9-456A-4DAB-B4F3-ACF838C121DE}"

///|
// Cache connection metadata has no cell dimensions; positioned content belongs to drawings.
fn Session::slicer_extension(
  self : Session,
  current : Sheet,
  tree : Tree,
  node : @xml.Node,
  sheets~ : Array[Sheet] = self.sheets,
) -> Bool raise @failure.Failure {
  if node.uri != spreadsheet_uri || node.name != "extLst" {
    return false
  }
  let entries = tree.children.get(node.id).unwrap_or([])
  if !entries.any(ext => {
      ext
      .attribute("uri")
      .map(uri => uri.to_upper() == slicer_list_extension)
      .unwrap_or(false)
    }) ||
    !entries.all(ext => {
      ext.uri == spreadsheet_uri &&
      ext.name == "ext" &&
      ext
      .attribute("uri")
      .map(uri => {
        uri.to_upper() == slicer_list_extension ||
        (
          uri == sparkline_extension_uri &&
          sparkline_reason(current, sheets).is_empty()
        )
      })
      .unwrap_or(false)
    }) {
    return false
  }
  ignore(
    self.slicer_parts(
      current.id,
      current.document,
      slicer_list_extension,
      "slicerList",
      "slicer",
      "slicer",
    ),
  )
  true
}

///|
fn Tree::slicer_children(
  self : Tree,
  parent : Int32,
  name : String,
) -> Array[@xml.Node] {
  self.children
  .get(parent)
  .unwrap_or([])
  .filter(node => node.uri == slicer_uri && node.name == name)
}

///|
fn Tree::slicer_node(
  self : Tree,
  parent : Int32,
  name : String,
) -> @xml.Node raise @failure.Failure {
  guard self.slicer_children(parent, name) is [node] else {
    @failure.reject("protected-content", "Missing or duplicate slicer " + name)
  }
  node
}

///|
fn slicer_node_profile(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == slicer_uri &&
    node.text.trim().is_empty() &&
    node.attributes.all(attribute => {
      (attribute.uri.is_empty() && attributes.contains(attribute.name)) ||
      (
        attribute.uri ==
        "http://schemas.microsoft.com/office/spreadsheetml/2016/revision10" &&
        attribute.name == "uid"
      ) ||
      (
        attribute.uri ==
        "http://schemas.openxmlformats.org/markup-compatibility/2006" &&
        attribute.name == "Ignorable"
      )
    }) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(child => child.uri == slicer_uri && children.contains(child.name)) else {
    @failure.reject(
      "protected-content",
      "Unsupported slicer source: " + node.name,
    )
  }
}

///|
fn slicer_text(
  node : @xml.Node,
  name : String,
  fallback~ : String = "",
) -> String raise @failure.Failure {
  let value = decode_text(node.attribute(name).unwrap_or(fallback))
  guard !value.trim().is_empty() &&
    value.length() <= 255 &&
    @xml.valid_text(value) else {
    @failure.reject("protected-content", "Invalid slicer " + name)
  }
  value
}

///|
fn Session::slicer_relation(
  self : Session,
  owner : String,
  id : String,
  kind : String,
) -> String raise @failure.Failure {
  guard self
    .relationships()
    .filter(link => link.owner == owner && link.id == id)
    is [link] &&
    !link.external &&
    link.kind == slicer_relationship_uri + kind else {
    @failure.reject(
      "protected-content", "Invalid or external slicer relationship",
    )
  }
  guard self
    .part_xml("[Content_Types].xml")
    .nodes()
    .filter(node => {
      node.name == "Override" &&
      node.uri == "http://schemas.openxmlformats.org/package/2006/content-types" &&
      node
      .attribute("PartName")
      .map(path => path.to_lower() == "/" + link.target.to_lower())
      .unwrap_or(false)
    })
    is [content] &&
    content.attribute("ContentType") ==
    Some("application/vnd.ms-excel." + kind + "+xml") else {
    @failure.reject(
      "protected-content", "Slicer content type disagrees with its relationship",
    )
  }
  link.target
}

///|
fn Session::slicer_parts(
  self : Session,
  owner : String,
  document : @xml.Document,
  extension : String,
  container : String,
  child : String,
  kind : String,
) -> Array[String] raise @failure.Failure {
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  let extensions = tree
    .one(root.id, "extLst")
    .map(list => tree.all(list.id, "ext"))
    .unwrap_or([])
  let matches = extensions.filter(node => {
    node
    .attribute("uri")
    .map(uri => uri.to_upper() == extension)
    .unwrap_or(false)
  })
  guard matches.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate slicer extension")
  }
  guard matches is [ext] else { return [] }
  guard ext.attributes.all(attribute => {
      attribute.uri.is_empty() && attribute.name == "uri"
    }) &&
    ext.text.trim().is_empty() &&
    tree.children.get(ext.id).unwrap_or([]).length() == 1 else {
    @failure.reject("protected-content", "Unknown slicer extension metadata")
  }
  let list = tree.slicer_node(ext.id, container)
  slicer_node_profile(tree, list, [], [child])
  let entries = tree.slicer_children(list.id, child)
  guard !entries.is_empty() && entries.length() <= 64 else {
    @failure.reject("limit-exceeded", "Slicer references exceed budget")
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
      is Some(id) else {
      @failure.reject("protected-content", "Invalid slicer reference")
    }
    let part = self.slicer_relation(owner, id, kind)
    guard !seen.contains(part) else {
      @failure.reject("protected-content", "Duplicate slicer part reference")
    }
    seen[part] = true
    part
  })
}
