///|
fn section_contents(node : @xml.Node, markup : String) -> @xml.SourceChange {
  if node.empty {
    insertion(node, markup)
  } else {
    {
      node: node.id,
      offset: node.opening_end - node.start,
      length: node.closing_start - node.opening_end,
      xml: markup,
    }
  }
}

///|
fn Section::markup(
  self : Section,
  tree : Tree,
) -> String raise @failure.Failure {
  let members = "<ods:sldIdLst xmlns:ods=\"\{creation_uri}\">" +
    self.slides.map(id => "<ods:sldId id=\"\{id}\"/>").join("") +
    "</ods:sldIdLst>"
  if self.node < 0 {
    return "<ods:section xmlns:ods=\"\{creation_uri}\" id=\"\{self.id}\" name=\"\{xml_attribute(self.name)}\">\{members}</ods:section>"
  }
  let node = tree.nodes[self.node]
  let changes : Array[@xml.SourceChange] = []
  if node.attribute("name") != Some(self.name) {
    changes.push(
      attribute_change({ tree, node, }, "name", xml_attribute(self.name)),
    )
  }
  let list = tree.required(node.id, "sldIdLst", uri=creation_uri)
  let before = tree
    .all(list.id, "sldId", uri=creation_uri)
    .map(n => source_identity(n.attribute("id").unwrap_or("")))
  if before != self.slides {
    changes.push({
      node: node.id,
      offset: list.start - node.start,
      length: list.end - list.start,
      xml: members,
    })
  }
  if changes.is_empty() {
    return tree.document.source()[node.start:node.end].to_owned()
  }
  let updated = tree.document.edit_source(changes).0
  let node = updated.node(self.node)
  updated.source()[node.start:node.end].to_owned()
}

///|
fn write_sections(
  main : Tree,
  sections : Array[Section],
  edits : Array[(String, @xml.Edit)],
) -> Tree raise @failure.Failure {
  let container = section_container(main)
  if container is None && sections.is_empty() {
    return main
  }
  let markup = sections.map(s => s.markup(main)).join("")
  let change = if container is Some((ext, list)) {
    if sections.is_empty() {
      let parent = main.nodes[ext.parent]
      let source = main.document.source()[parent.start:parent.end]
      if main.children.get(parent.id).unwrap_or([]).length() == 1 &&
        parent.attributes.is_empty() &&
        parent.text.trim().is_empty() &&
        !source.contains("<!--") &&
        !source.contains("<?") {
        remove_slide_node(main, parent)
      } else {
        remove_slide_node(main, ext)
      }
    } else {
      section_contents(list, markup)
    }
  } else {
    let root = main.root("presentation")
    let markup = "<od:ext xmlns:od=\"\{presentation_uri}\" uri=\"\{section_extension}\"><ods:sectionLst xmlns:ods=\"\{creation_uri}\">\{markup}</ods:sectionLst></od:ext>"
    if main.one(root.id, "extLst", uri=presentation_uri) is Some(list) {
      insertion(list, markup)
    } else {
      insertion(
        root,
        "<od:extLst xmlns:od=\"\{presentation_uri}\">\{markup}</od:extLst>",
      )
    }
  }
  let (document, edit) = main.document.edit_source([change])
  if document.source() == main.document.source() {
    return main
  }
  let updated = Tree::new(main.part, document)
  ignore(read_sections(updated))
  edits.push((main.part, edit))
  updated
}

///|
fn reorder_section_slides(
  main : Tree,
  ids : Array[String],
) -> @xml.SourceChange raise @failure.Failure {
  let list = main.required(
    main.root("presentation").id,
    "sldIdLst",
    uri=presentation_uri,
  )
  let nodes = main.all(list.id, "sldId", uri=presentation_uri)
  guard nodes.length() == ids.length() else {
    @failure.reject("invalid-operation", "Section slide count changed")
  }
  let fragments : Map[String, String] = Map([])
  let mut start = list.opening_end
  for node in nodes {
    fragments[source_identity(node.attribute("id").unwrap_or(""))] = main.document.source()[start:node.end].to_owned()
    start = node.end
  }
  let markup = ids
    .map(id => {
      let fragment = fragments
        .get(id)
        .unwrap_or_else(() => {
          @failure.reject("invalid-operation", "Unknown section slide")
        })
      ignore(fragments.remove(id))
      fragment
    })
    .join("") +
    main.document.source()[start:list.closing_start].to_owned()
  guard fragments.is_empty() else {
    @failure.reject("invalid-operation", "Section slides were omitted")
  }
  section_contents(list, markup)
}
