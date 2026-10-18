///|
pub(all) struct CustomShow {
  id : String
  name : String
  slides : Array[String]
} derive(Eq, ToJson)

///|
pub extend CustomShow with Eq::{equal, not_equal}

///|
pub extend CustomShow with ToJson::{to_json}

///|
fn custom_show_node(
  tree : Tree,
  node : @xml.Node,
  name : String,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == presentation_uri &&
    node.name == name &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => n.uri == presentation_uri && children.contains(n.name)) else {
    @failure.reject(
      "protected-content", "Extended custom show content is protected",
    )
  }
}

///|
fn Session::validate_custom_shows(
  self : Session,
  items : Array[CustomShow],
) -> Unit raise @failure.Failure {
  guard items.length() <= 32 else {
    @failure.reject("limit-exceeded", "Custom shows exceed 32")
  }
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let mut count = 0
  for item in items {
    let id = number(item.id, 0, 4294967295).to_int64().to_string()
    guard id == item.id &&
      !ids.contains(id) &&
      !item.name.trim().is_empty() &&
      item.name.length() <= 255 &&
      @xml.valid_text(item.name) &&
      !names.contains(item.name.to_lower()) else {
      @failure.reject(
        "invalid-operation", "Invalid or duplicate custom show identity or name",
      )
    }
    ids[id] = true
    names[item.name.to_lower()] = true
    count += item.slides.length()
    guard item.slides.length() <= 256 && count <= 4096 else {
      @failure.reject("limit-exceeded", "Custom show entries exceed budget")
    }
    for slide in item.slides {
      ignore(self.index(slide))
    }
  }
}

///|
fn Session::custom_show_links(
  self : Session,
) -> Map[String, String] raise @failure.Failure {
  let links : Map[String, String] = Map([])
  for link in self.relationships() {
    if link.owner == self.main.part &&
      !link.external &&
      link.kind == relationship_uri + "/slide" {
      links[link.id] = link.target
    }
  }
  links
}

///|
fn Session::read_custom_shows(
  self : Session,
  tree~ : Tree = self.main,
) -> Array[CustomShow] raise @failure.Failure {
  guard tree.one(
      tree.root("presentation").id,
      "custShowLst",
      uri=presentation_uri,
    )
    is Some(list) else {
    return []
  }
  custom_show_node(tree, list, "custShowLst", [], ["custShow"])
  let source = tree.document.source()[list.start:list.end]
  guard tree.children.get(list.id).unwrap_or([]).length() <= 32 else {
    @failure.reject("limit-exceeded", "Custom shows exceed 32")
  }
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque custom show source is protected",
    )
  }
  let links = self.custom_show_links()
  let items = tree.children
    .get(list.id)
    .unwrap_or([])
    .map(node => {
      custom_show_node(tree, node, "custShow", ["id", "name"], ["sldLst"])
      let members = tree.required(node.id, "sldLst", uri=presentation_uri)
      guard tree.children.get(members.id).unwrap_or([]).length() <= 256 else {
        @failure.reject("limit-exceeded", "Custom show entries exceed 256")
      }
      custom_show_node(tree, members, "sldLst", [], ["sld"])
      let slides = tree.children
        .get(members.id)
        .unwrap_or([])
        .map(slide => {
          guard slide.uri == presentation_uri &&
            slide.name == "sld" &&
            slide.text.trim().is_empty() &&
            slide.attributes.length() == 1 &&
            slide.attributes[0].uri == relationship_uri &&
            slide.attributes[0].name == "id" &&
            tree.children.get(slide.id).unwrap_or([]).is_empty() &&
            links.get(slide.attributes[0].value) is Some(part) else {
            @failure.reject(
              "protected-content", "Invalid custom show slide reference",
            )
          }
          part
        })
      {
        id: number(node.attribute("id").unwrap_or(""), 0, 4294967295)
        .to_int64()
        .to_string(),
        name: node.attribute("name").unwrap_or(""),
        slides,
      }
    })
  self.validate_custom_shows(items)
  items
}

///|
fn Session::custom_show_query(self : Session) -> Json {
  {
    "items": self.read_custom_shows(),
    "reason": self.slide_visibility_reason(),
  } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}

///|
fn Session::check_removed_shows(
  self : Session,
  ids : Array[String],
) -> Unit raise @failure.Failure {
  guard !ids.is_empty() else { return }
  let names : Map[String, Bool] = Map([])
  for _, name in self.opc.names {
    names[name] = true
  }
  for name in self.parts.keys() {
    names[name] = true
  }
  for slide in self.slides {
    names[slide.tree.part] = true
  }
  for name in names.keys() {
    if !name.to_lower().has_suffix(".xml") || self.removed.contains(name) {
      continue
    }
    let document = self.part_document(name)
    for node in document.nodes() {
      guard !(node.name == "custShow" &&
        !(name == self.main.part &&
        node.parent >= 0 &&
        document.node(node.parent).name == "custShowLst") &&
        node
        .attribute("id")
        .map(id => {
          ids.contains(number(id, 0, 4294967295).to_int64().to_string())
        })
        .unwrap_or(true)) &&
        !node.attributes.any(a => {
          a.name == "action" &&
          a.value.to_lower().has_prefix("ppaction://customshow")
        }) else {
        @failure.reject(
          "protected-content", "A removed custom show is referenced by presentation settings or actions",
        )
      }
    }
  }
}

///|
fn Session::set_custom_shows(
  self : Session,
  items : Array[CustomShow],
) -> Json raise @failure.Failure {
  guard items.length() <= 32 else {
    @failure.reject("limit-exceeded", "Custom shows exceed 32")
  }
  let previous = self.read_custom_shows()
  let mut next = previous.fold(init=-1L, (next, item) => {
      next.max(number(item.id, 0, 4294967295).to_int64())
    }) +
    1L
  let items = items.map(item => {
    if item.id.is_empty() {
      guard next <= 4294967295L else {
        @failure.reject("limit-exceeded", "Custom show identities exhausted")
      }
      let id = next.to_string()
      next += 1L
      { ..item, id, }
    } else {
      guard previous.any(old => old.id == item.id) else {
        @failure.reject("invalid-operation", "Custom show no longer exists")
      }
      item
    }
  })
  self.validate_custom_shows(items)
  if previous == items {
    return self.query()
  }
  self.check_removed_shows(
    previous
    .filter(old => !items.any(item => item.id == old.id))
    .map(item => item.id),
  )
  let tree = self.main
  let root = tree.root("presentation")
  let container = tree.one(root.id, "custShowLst", uri=presentation_uri)
  let nodes = container
    .map(list => tree.children.get(list.id).unwrap_or([]))
    .unwrap_or([])
  let links = self.custom_show_links()
  let by_part : Map[String, String] = Map([])
  for id, part in links {
    by_part[part] = id
  }
  let content = items
    .map(item => {
      if previous.search_by(old => old == item) is Some(index) {
        let node = nodes[index]
        return tree.document.source()[node.start:node.end].to_owned()
      }
      let slides = item.slides
        .map(part => "<od:sld odr:id=\"\{xml_attribute(by_part[part])}\"/>")
        .join("")
      "<od:custShow xmlns:od=\"\{presentation_uri}\" xmlns:odr=\"\{relationship_uri}\" id=\"\{item.id}\" name=\"\{xml_attribute(item.name)}\"><od:sldLst>\{slides}</od:sldLst></od:custShow>"
    })
    .join("")
  let change = if container is Some(list) {
    if items.is_empty() {
      remove_slide_node(tree, list)
    } else {
      section_contents(list, content)
    }
  } else {
    let markup = "<od:custShowLst xmlns:od=\"\{presentation_uri}\">\{content}</od:custShowLst>"
    let following_names = [
      "photoAlbum", "custDataLst", "kinsoku", "defaultTextStyle", "modifyVerifier",
      "extLst",
    ]
    let following = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == presentation_uri && following_names.contains(node.name)
      })
    if following is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    }
  }
  let (document, edit) = tree.document.edit_source([change])
  let main = Tree::new(tree.part, document)
  ignore(self.read_custom_shows(tree=main))
  self.commit_slides(main, self.slides, [(main.part, edit)], self.selection)
  self.query()
}
