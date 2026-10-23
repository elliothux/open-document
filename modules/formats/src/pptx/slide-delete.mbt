///|
fn Session::part_document(
  self : Session,
  part : String,
) -> @xml.Document raise @failure.Failure {
  if part == self.main.part {
    return self.main.document
  }
  if self.slides.iter().find_first(slide => slide.tree.part == part)
    is Some(slide) {
    return slide.tree.document
  }
  self.parts.get(part).unwrap_or_else(() => self.opc.xml(part))
}

///|
fn remove_slide_node(tree : Tree, node : @xml.Node) -> @xml.SourceChange {
  {
    node: node.parent,
    offset: node.start - tree.nodes[node.parent].start,
    length: node.end - node.start,
    xml: "",
  }
}

///|
fn Tree::slide_reference(self : Tree, node : @xml.Node) -> Bool {
  if node.uri != presentation_uri || node.parent < 0 {
    return false
  }
  let parent = self.nodes[node.parent]
  if node.name == "sldId" {
    return parent.uri == presentation_uri &&
      parent.name == "sldIdLst" &&
      parent.parent == self.document.nodes()[0].id
  }
  if node.name != "sld" ||
    parent.uri != presentation_uri ||
    parent.name != "sldLst" ||
    parent.parent < 0 {
    return false
  }
  let show = self.nodes[parent.parent]
  if show.uri != presentation_uri || show.name != "custShow" || show.parent < 0 {
    return false
  }
  let list = self.nodes[show.parent]
  list.uri == presentation_uri &&
  list.name == "custShowLst" &&
  list.parent == self.document.nodes()[0].id
}

///|
fn Session::delete_slides(
  self : Session,
  targets : Array[String],
  section~ : String? = None,
) -> Json raise @failure.Failure {
  let deleted = self.slides.filter(slide => targets.contains(slide.tree.part))
  guard deleted.length() < self.slides.length() else {
    @failure.reject(
      "invalid-slide", "A presentation must retain at least one slide",
    )
  }
  let links = self.relationships()
  let names : Array[String] = []
  for slide in deleted {
    let target = slide.tree.part
    names.append([target, relationship_part(target)])
    for kind in ["notesSlide", "comments", "modernComments"] {
      let owned = links
        .iter()
        .filter(link => {
          link.owner == target &&
          !link.external &&
          link.kind ==
          (if kind == "modernComments" {
            modern_comment_relationship + "/comments"
          } else {
            relationship_uri + "/" + kind
          })
        })
        .collect()
      guard owned.length() <= 1 else {
        @failure.reject(
          "protected-content", "Multiple slide notes or comment owners are unsupported",
        )
      }
      if owned.get(0) is Some(link) {
        guard links
          .iter()
          .all(incoming => {
            incoming.external ||
            incoming.target != link.target ||
            incoming.owner == target
          }) else {
          @failure.reject(
            "protected-content", "Shared slide notes or comments require ownership support",
          )
        }
        names.push(link.target)
        let path = relationship_part(link.target)
        if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
          names.push(path)
        }
      }
    }
  }
  let removed : Map[String, @xml.Document] = Map([])
  let mut bytes = 0L
  for name in names {
    guard !removed.contains(name) else {
      @failure.reject("protected-content", "Cyclic slide resource ownership")
    }
    let document = self.part_document(name)
    bytes += document.source().length().to_int64() * 2
    guard bytes <= 4194304L else {
      @failure.reject("limit-exceeded", "Deleted slide exceeds history budget")
    }
    removed[name] = document
  }
  let incoming : Map[String, Array[String]] = Map([])
  for link in links {
    if link.external ||
      !removed.contains(link.target) ||
      removed.contains(link.owner) {
      continue
    }
    guard targets.contains(link.target) &&
      [relationship_uri + "/slide", relationship_uri + "/hyperlink"].contains(
        link.kind,
      ) &&
      !link.owner.is_empty() else {
      @failure.reject(
        "protected-content", "Unknown incoming slide resource reference",
      )
    }
    if incoming.get(link.owner) is Some(ids) {
      ids.push(link.id)
    } else {
      incoming[link.owner] = [link.id]
    }
  }
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let slides = self.slides.filter(slide => !targets.contains(slide.tree.part))
  let mut main = self.main
  for owner, ids in incoming {
    let original = self.part_document(owner)
    let tree = Tree::new(owner, original)
    let changes : Array[@xml.SourceChange] = []
    for node in original.nodes() {
      let references = node.attributes.filter(a => {
        a.uri == relationship_uri && ids.contains(a.value)
      })
      if references.is_empty() {
        continue
      }
      guard references.iter().all(a => a.name == "id") &&
        (
          (owner == main.part && tree.slide_reference(node)) ||
          (
            node.uri == drawing_uri &&
            ["hlinkClick", "hlinkMouseOver"].contains(node.name)
          )
        ) else {
        @failure.reject(
          "protected-content",
          "Unknown XML reference to the deleted slide",
          part=owner,
        )
      }
      changes.push(remove_slide_node(tree, node))
    }
    let root = original.nodes()[0]
    guard !changes.is_empty() ||
      (
        root.uri == presentation_uri &&
        ["sld", "sldLayout", "sldMaster"].contains(root.name)
      ) else {
      @failure.reject(
        "protected-content",
        "Implicit incoming slide reference requires ownership support",
        part=owner,
      )
    }
    if !changes.is_empty() {
      let (document, edit) = original.edit_source(changes)
      edits.push((owner, edit))
      if owner == main.part {
        main = Tree::new(owner, document)
      } else {
        parts[owner] = document
      }
    }
    let path = relationship_part(owner)
    let original = self.part_document(path)
    let tree = Tree::new(path, original)
    let changes = original
      .nodes()
      .filter(node => {
        node.parent == original.nodes()[0].id &&
        node.attribute("Id").map(id => ids.contains(id)).unwrap_or(false)
      })
      .map(node => remove_slide_node(tree, node))
    let (document, edit) = original.edit_source(changes.iter().collect())
    parts[path] = document
    edits.push((path, edit))
  }
  let path = "[Content_Types].xml"
  let original = self.part_document(path)
  let tree = Tree::new(path, original)
  let changes = original
    .nodes()
    .filter(node => {
      node.name == "Override" &&
      node
      .attribute("PartName")
      .map(name => {
        name.has_prefix("/") &&
        names.any(path => path.to_lower() == name[1:].to_owned().to_lower())
      })
      .unwrap_or(false)
    })
    .map(node => remove_slide_node(tree, node))
  if !changes.is_empty() {
    let (document, edit) = original.edit_source(changes.iter().collect())
    parts[path] = document
    edits.push((path, edit))
  }
  for name in names {
    parts.remove(name)
  }
  let removed_parts = [
    ..self.removed,
    ..names.filter(name => self.opc.names.contains(name.to_lower())),
  ]
  for i in 0..<slides.length() {
    let part = slides[i].tree.part
    if parts.get(part) is Some(document) {
      slides[i] = read_slide(
        self.opc,
        main,
        self.cache,
        Tree::new(part, document),
        index=i,
        date_time=self.date_time,
        parts~,
      )
      parts.remove(part)
    }
  }
  let members = section_slide_ids(main)
  let sections = read_sections(self.main)
    .filter(item => Some(item.id) != section)
    .map(item => {
      ..item,
      slides: item.slides.filter(id => members.contains(id)),
    })
  main = write_sections(main, sections, edits)
  let slides = self.ordered_slides(main, slides, parts~, removed=removed_parts)
  let after = if targets.contains(self.selection.slide) {
    let index = self.index(self.selection.slide)
    let next = self.slides[index:]
      .iter()
      .find_first(slide => !targets.contains(slide.tree.part))
      .unwrap_or(slides.last().unwrap())
    {
      slide: next.tree.part,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    }
  } else {
    self.selection
  }
  self.commit_slides(main, slides, edits, after, parts~, deleted~, removed~)
  self.query()
}
