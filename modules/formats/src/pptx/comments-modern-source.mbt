///|
let comment_anchor_uri = "http://schemas.microsoft.com/office/powerpoint/2013/main/command"

///|
let comment_extension_id = "{6950BFC3-D8DA-4A85-94F7-54DA5524770B}"

///|
fn modern_comment_extension(tree : Tree, node : @xml.Node) -> Bool {
  let children = tree.children.get(node.id).unwrap_or([])
  node.uri == presentation_uri &&
  node.name == "ext" &&
  tree.nodes
  .get(node.parent)
  .map(n => {
    n.uri == presentation_uri &&
    n.name == "extLst" &&
    n.parent == tree.document.nodes()[0].id
  })
  .unwrap_or(false) &&
  node.attribute("uri").map(s => s.to_upper()) == Some(comment_extension_id) &&
  node.attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
  node.text.trim().is_empty() &&
  children is [reference] &&
  reference.uri == modern_comment_uri &&
  reference.name == "commentRel" &&
  reference.attributes is [attribute] &&
  attribute.uri == relationship_uri &&
  attribute.name == "id" &&
  !attribute.value.is_empty() &&
  reference.text.trim().is_empty() &&
  tree.children.get(reference.id).unwrap_or([]).is_empty()
}

///|
fn Session::check_comment_reference(
  self : Session,
  owner : String,
  link : @opc.Relationship?,
) -> Unit raise @failure.Failure {
  guard self.slides.iter().find_first(s => s.tree.part == owner) is Some(page) else {
    return
  }
  let tree = page.tree
  let list = tree.one(tree.root("sld").id, "extLst", uri=presentation_uri)
  let extensions = list
    .map(list => {
      tree
      .all(list.id, "ext", uri=presentation_uri)
      .filter(node => {
        node.attribute("uri").map(s => s.to_upper()) ==
        Some(comment_extension_id)
      })
    })
    .unwrap_or([])
  if link is Some(link) &&
    link.kind == modern_comment_relationship + "/comments" {
    guard extensions is [ext] &&
      modern_comment_extension(tree, ext) &&
      tree.children[ext.id][0].attribute("id", uri=relationship_uri) ==
      Some(link.id) else {
      @failure.reject(
        "protected-content", "Modern comment entry does not match its relationship",
      )
    }
  } else {
    guard extensions.is_empty() else {
      @failure.reject(
        "protected-content", "Orphan modern comment entry is protected",
      )
    }
  }
}

///|
fn Session::add_comment_reference(
  self : Session,
  owner : String,
  id : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let page = self.slides[self.index(owner)]
  let tree = page.tree
  let root = tree.root("sld")
  let markup = "<p:ext xmlns:p=\"\{presentation_uri}\" uri=\"\{comment_extension_id}\"><mc:commentRel xmlns:mc=\"\{modern_comment_uri}\" xmlns:r=\"\{relationship_uri}\" r:id=\"\{id}\"/></p:ext>"
  let change = match tree.one(root.id, "extLst", uri=presentation_uri) {
    Some(list) => insertion(list, markup)
    None =>
      insertion(
        root,
        "<p:extLst xmlns:p=\"\{presentation_uri}\">\{markup}</p:extLst>",
      )
  }
  let (document, edit) = tree.document.edit_source([change])
  parts[owner] = document
  edits.push((owner, edit))
}

///|
fn Session::comment_slide_id(
  self : Session,
  slide : String,
) -> String raise @failure.Failure {
  let link = self
    .relationships()
    .iter()
    .find_first(l => {
      l.owner == self.main.part &&
      l.target == slide &&
      l.kind == relationship_uri + "/slide"
    })
    .unwrap()
  let list = self.main.required(
    self.main.root("presentation").id,
    "sldIdLst",
    uri=presentation_uri,
  )
  let node = self.main
    .all(list.id, "sldId", uri=presentation_uri)
    .iter()
    .find_first(n => n.attribute("id", uri=relationship_uri) == Some(link.id))
    .unwrap()
  comment_uint(node.attribute("id").unwrap())
}

///|
fn comment_anchor_markup(slide : String) -> String {
  "<pc:sldMkLst xmlns:pc=\"\{comment_anchor_uri}\"><pc:docMk/><pc:sldMk sldId=\"\{slide}\"/></pc:sldMkLst>"
}

///|
fn modern_comment_anchor(
  tree : Tree,
  node : @xml.Node,
) -> @xml.Node? raise @failure.Failure {
  let anchor = tree.one(node.id, "sldMkLst", uri=comment_anchor_uri)
  if anchor is Some(anchor) {
    let raw = tree.document.source()[anchor.start:anchor.end]
    guard !raw.contains("<!--") && !raw.contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated comment anchors are protected",
      )
    }
    comment_markup(tree, anchor, [], [
      (comment_anchor_uri, "docMk"),
      (comment_anchor_uri, "sldMk"),
    ])
    let document = tree.required(anchor.id, "docMk", uri=comment_anchor_uri)
    let slide = tree.required(anchor.id, "sldMk", uri=comment_anchor_uri)
    comment_markup(tree, document, [], [])
    comment_markup(tree, slide, ["sldId", "cId"], [])
    guard document.start < slide.start else {
      @failure.reject("protected-content", "Invalid comment anchor order")
    }
    ignore(number(slide.attribute("sldId").unwrap_or(""), 256, 2147483647))
    if slide.attribute("cId") is Some(id) {
      ignore(comment_uint(id))
    }
  }
  anchor
}

///|
fn Session::check_comment_anchors(
  self : Session,
  tree : Tree,
  slide : String,
) -> Unit raise @failure.Failure {
  let id = self.comment_slide_id(slide)
  for
    node in tree.all(
      tree.root("cmLst", uri=modern_comment_uri).id,
      "cm",
      uri=modern_comment_uri,
    ) {
    if modern_comment_anchor(tree, node) is Some(anchor) {
      guard tree
        .required(anchor.id, "sldMk", uri=comment_anchor_uri)
        .attribute("sldId")
        .map(comment_uint) ==
        Some(id) else {
        @failure.reject(
          "protected-content", "Comment anchor belongs to another slide",
        )
      }
    }
  }
}
