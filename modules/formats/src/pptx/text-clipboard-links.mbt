///|
let clipboard_link_attributes : ReadOnlyArray[String] = [
  "tooltip", "tgtFrame", "history", "highlightClick", "endSnd",
]

///|
fn check_clipboard_link_metadata(
  node : @xml.Node,
) -> Unit raise @failure.Failure {
  guard node.attributes.all(a => a.value.length() <= 2048) else {
    @failure.reject(
      "protected-content", "Clipboard link metadata exceeds 2048 units",
    )
  }
  for name in ["history", "highlightClick", "endSnd"] {
    ignore(flag(node, name))
  }
}

///|
fn Session::clipboard_text_link(
  self : Session,
  properties : Ref?,
  links : ReadOnlyArray[@opc.Relationship],
  destinations : Set[String],
) -> String? raise @failure.Failure {
  guard properties is Some(properties) &&
    hyperlink_node(properties) is Some(node) else {
    return None
  }
  let (kind, target) = self
    .read_hyperlink_at(Some(properties), properties.tree.part, links)
    .unwrap()
  guard kind == "external" || kind == "action" else {
    @failure.reject(
      "protected-content", "Slide links require transferring their destination slide",
    )
  }
  check_clipboard_link_metadata(node)
  destinations.add(kind + "\n" + target)
  guard destinations.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Text clipboard exceeds 256 link destinations",
    )
  }
  let metadata = StringBuilder()
  for a in node.attributes {
    if a.uri.is_empty() && clipboard_link_attributes.contains(a.name) {
      metadata.write_string(" \{a.name}='\{xml_attribute(a.value)}'")
    }
  }
  Some(
    "<od:link xmlns:od='\{text_fragment_uri}' kind='\{kind}' target='\{xml_attribute(target)}'\{metadata.to_string()}/>",
  )
}

///|
fn Session::bind_text_fragment_links(
  self : Session,
  tree : Tree,
  owner : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Tree raise @failure.Failure {
  let links = self.relationships()
  let resolved : Map[String, String] = Map([])
  let changes : Array[@xml.SourceChange] = []
  for node in tree.document.nodes() {
    if node.uri != text_fragment_uri || node.name != "link" {
      continue
    }
    let kind = node.attribute("kind").unwrap_or("")
    let target = node.attribute("target").unwrap_or("")
    guard kind == "external" || kind == "action" else {
      @failure.reject(
        "protected-content", "Unsupported clipboard link destination",
      )
    }
    self.check_hyperlink_target(kind, target)
    check_clipboard_link_metadata(node)
    let key = kind + "\n" + target
    let relation = if resolved.get(key) is Some(relation) {
      relation
    } else {
      guard resolved.length() < 256 else {
        @failure.reject(
          "limit-exceeded", "Text clipboard exceeds 256 link destinations",
        )
      }
      let relation = if kind == "action" {
        ""
      } else {
        self.hyperlink_relationship(
          owner, kind, target, links, parts, created, edits,
        )
      }
      resolved[key] = relation
      relation
    }
    let metadata = {
      ..node,
      attributes: node.attributes.filter(a => {
        clipboard_link_attributes.contains(a.name)
      }),
    }
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: hyperlink_markup(Some(metadata), kind, relation, target~),
    })
  }
  if changes.is_empty() {
    return tree
  }
  let (document, _) = tree.document.edit_source(changes)
  Tree::new(tree.part, document)
}
