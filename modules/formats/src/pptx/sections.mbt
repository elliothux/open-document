///|
let section_extension = "{521415D9-36F7-43E2-AB2F-B90AF26B5E84}"

///|
priv struct Section {
  node : Int32
  id : String
  name : String
  slides : Array[String]
}

///|
fn section_guid(value : String) -> Bool {
  if value.length() != 38 || value[0] != '{' || value[37] != '}' {
    return false
  }
  for i, ch in value.iter2() {
    if i == 0 || i == 37 {
      continue
    }
    if [9, 14, 19, 24].contains(i) {
      if ch != '-' {
        return false
      }
    } else if !ch.is_ascii_hexdigit() {
      return false
    }
  }
  true
}

///|
fn section_node(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == creation_uri &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => n.uri == creation_uri && children.contains(n.name)) else {
    @failure.reject(
      "protected-content",
      "Unknown section content is protected",
      part=tree.part,
    )
  }
}

///|
fn section_slide_ids(tree : Tree) -> Array[String] raise @failure.Failure {
  tree
  .all(
    tree.required(
      tree.root("presentation").id,
      "sldIdLst",
      uri=presentation_uri,
    ).id,
    "sldId",
    uri=presentation_uri,
  )
  .map(n => source_identity(n.attribute("id").unwrap_or("")))
}

///|
fn section_container(
  tree : Tree,
) -> (@xml.Node, @xml.Node)? raise @failure.Failure {
  let list = tree.one(
    tree.root("presentation").id,
    "extLst",
    uri=presentation_uri,
  )
  let matches = list
    .map(list => {
      tree
      .all(list.id, "ext", uri=presentation_uri)
      .filter(n => {
        n.attribute("uri").map(v => v.to_upper()) == Some(section_extension)
      })
    })
    .unwrap_or([])
  guard matches.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate section extension")
  }
  if matches.get(0) is Some(ext) {
    guard ext.text.trim().is_empty() &&
      ext.attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
      tree.children.get(ext.id).unwrap_or([]) is [section_list] &&
      section_list.uri == creation_uri &&
      section_list.name == "sectionLst" else {
      @failure.reject(
        "protected-content", "Unknown section extension is protected",
      )
    }
    let source = tree.document.source()[ext.start:ext.end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Retained section markup is protected",
      )
    }
    return Some((ext, section_list))
  }
  None
}

///|
fn read_sections(tree : Tree) -> Array[Section] raise @failure.Failure {
  let container = section_container(tree)
  for node in tree.document.nodes() {
    if node.uri == creation_uri && node.name == "sectionLst" {
      guard container is Some((_, list)) && node.id == list.id else {
        @failure.reject("protected-content", "Unknown section list placement")
      }
    }
  }
  guard container is Some((_, list)) else { return [] }
  section_node(tree, list, [], ["section"])
  let nodes = tree.all(list.id, "section", uri=creation_uri)
  guard nodes.length() <= 256 else {
    @failure.reject("limit-exceeded", "Sections exceed 256")
  }
  let ids = section_slide_ids(tree)
  let positions : Map[String, Int32] = Map([])
  for i, id in ids {
    positions[id] = i
  }
  let identities : Map[String, Bool] = Map([])
  let seen : Map[String, Bool] = Map([])
  let mut previous = -1
  let sections = nodes.map(node => {
    section_node(tree, node, ["id", "name"], ["sldIdLst"])
    let id = node.attribute("id").unwrap_or("")
    let name = node.attribute("name").unwrap_or("")
    guard section_guid(id) &&
      !identities.contains(id.to_upper()) &&
      name.length() <= 255 else {
      @failure.reject("protected-content", "Invalid section identity or name")
    }
    identities[id.to_upper()] = true
    let members = tree.required(node.id, "sldIdLst", uri=creation_uri)
    section_node(tree, members, [], ["sldId"])
    let nodes = tree.all(members.id, "sldId", uri=creation_uri)
    guard nodes.length() <= 256 else {
      @failure.reject("limit-exceeded", "Section slides exceed 256")
    }
    let slides = nodes.map(item => {
      section_node(tree, item, ["id"], [])
      let id = source_identity(item.attribute("id").unwrap_or(""))
      guard positions.get(id) is Some(position) &&
        !seen.contains(id) &&
        (previous < 0 || position == previous + 1) else {
        @failure.reject(
          "protected-content", "Sections require ordered contiguous slide identities",
        )
      }
      seen[id] = true
      previous = position
      id
    })
    Section::{ node: node.id, id, name, slides, }
  })
  guard previous < 0 || previous == ids.length() - 1 else {
    @failure.reject("protected-content", "Section coverage is incomplete")
  }
  sections
}

///|
fn Session::section_query(self : Session) -> Json {
  try {
    let sections = read_sections(self.main)
    let paths : Map[String, String] = Map([])
    for i, id in section_slide_ids(self.main) {
      paths[id] = self.slides[i].tree.part
    }
    let reason = self.slide_visibility_reason()
    {
      "items": sections.map(s => {
        let value : Json = {
          "id": s.id,
          "name": s.name,
          "slides": s.slides.map(id => paths[id]),
        }
        value
      }),
      "reason": reason,
    }
  } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}
