///|
fn layout_special_placeholder(source : Ref) -> Bool raise @failure.Failure {
  placeholder(source)
  .map(ph => ["dt", "ftr", "hdr", "sldNum"].contains(ph.0))
  .unwrap_or(false)
}

///|
fn layout_placeholder_enabled(
  source : Ref,
  layout : Tree,
  master : Tree,
) -> Bool raise @failure.Failure {
  if !layout_special_placeholder(source) {
    return true
  }
  let settings : Ref? = match
    layout.one(layout.root("sldLayout").id, "hf", uri=presentation_uri) {
    Some(node) => Some({ tree: layout, node, })
    None =>
      master
      .one(master.root("sldMaster").id, "hf", uri=presentation_uri)
      .map(node => { tree: master, node, })
  }
  guard settings is Some(settings) else { return false }
  let node = settings.node
  guard node.text.trim().is_empty() &&
    settings.tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() && ["dt", "ftr", "hdr", "sldNum"].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Unknown layout header and footer settings are protected",
    )
  }
  flag(node, placeholder(source).unwrap().0, default=true)
}

///|
fn layout_placeholder_content(
  source : Ref,
  reserved : Map[String, Bool],
  next : Int64,
  budget : @archive.Budget,
) -> (String, Int64) raise @failure.Failure {
  guard source.child("txBody", uri=presentation_uri) is Some(body) else {
    return ("<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>", next)
  }
  guard body.node.end - body.node.start <= 1048576 else {
    @failure.reject("limit-exceeded", "Layout footer text exceeds budget")
  }
  let markup = source.tree.standalone_markup(source.tree.document, body.node.id)
  guard markup.length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Layout footer namespaces exceed budget")
  }
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    source.tree.part,
    budget.xml_depth,
    budget.entry_bytes,
  )
  guard document
    .nodes()
    .all(node => node.attributes.all(a => a.uri != relationship_uri)) else {
    @failure.reject(
      "protected-content", "Layout footer relationships require copying support",
    )
  }
  let (copied, next) = copy_slide_objects(
    Tree::new(source.tree.part, document),
    source.tree.part,
    reserved,
    next,
    budget,
  )
  (copied.source(), next)
}
