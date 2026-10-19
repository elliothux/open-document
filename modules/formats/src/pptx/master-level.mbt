///|
fn master_level_change(
  tree : Tree,
  kind : String,
  level : Int,
  markup : String,
) -> @xml.SourceChange raise @failure.Failure {
  let (styles, category, paragraph) = master_text_style(tree, kind, level)
  if paragraph is Some(paragraph) {
    return {
      node: paragraph.node.parent,
      offset: paragraph.node.start - tree.nodes[paragraph.node.parent].start,
      length: paragraph.node.end - paragraph.node.start,
      xml: markup,
    }
  }
  if category is Some(category) {
    let later = tree.children
      .get(category.node.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == drawing_uri &&
        (
          node.name == "extLst" ||
          (node.name.has_prefix("lvl") && node.name > "lvl\{level+1}pPr")
        )
      })
    return if later is Some(node) {
      {
        node: category.node.id,
        offset: node.start - category.node.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(category.node, markup)
    }
  }
  let markup = "<p:\{kind}Style xmlns:p=\"\{presentation_uri}\">\{markup}</p:\{kind}Style>"
  if styles is Some(styles) {
    let order = ["titleStyle", "bodyStyle", "otherStyle", "extLst"]
    let rank = order.search(kind + "Style").unwrap()
    let later = tree.children
      .get(styles.node.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == presentation_uri &&
        order.search(node.name).unwrap_or(4) > rank
      })
    return if later is Some(node) {
      {
        node: styles.node.id,
        offset: node.start - styles.node.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(styles.node, markup)
    }
  }
  let root = tree.document.nodes()[0]
  let markup = "<p:txStyles xmlns:p=\"\{presentation_uri}\">\{markup}</p:txStyles>"
  if tree.one(root.id, "extLst", uri=presentation_uri) is Some(node) {
    { node: root.id, offset: node.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
}

///|
fn master_style_sources(
  tree : Tree,
  main : Tree,
  kind : String,
  level : Int,
) -> Array[Ref] raise @failure.Failure {
  let (_, category, own) = master_text_style(tree, kind, level)
  let defaults = main
    .one(main.document.nodes()[0].id, "defaultTextStyle", uri=presentation_uri)
    .map(node => { tree: main, node, })
  let sources = own.map(p => [p]).unwrap_or([])
  for container in [category, defaults] {
    if container is Some(container) {
      if container.node.name == "defaultTextStyle" &&
        container.child("lvl\{level+1}pPr") is Some(p) {
        sources.push(p)
      }
      if container.child("defPPr") is Some(p) {
        sources.push(p)
      }
    }
  }
  sources
}
