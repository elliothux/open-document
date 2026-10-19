///|
fn Session::master_deletion(
  self : Session,
  part : String,
) -> (Array[String], @xml.Node, String) raise @failure.Failure {
  let choice = self.source_choice(part)
  guard choice.kind == "master" else {
    @failure.reject("invalid-slide", "Select a master source")
  }
  guard self.master_choices().length() > 1 else {
    @failure.reject("protected-content", "Keep at least one slide master")
  }
  let paths = [part, relationship_part(part)]
  for layout in self.layout_choices() {
    if layout.master.part == part {
      paths.append([layout.tree.part, relationship_part(layout.tree.part)])
    }
  }
  let links = self
    .relationships()
    .filter(link => {
      !link.external &&
      paths.contains(link.target) &&
      !paths.contains(link.owner)
    })
  let main_links = links.filter(link => {
    link.owner == self.main.part &&
    link.target == part &&
    link.kind == relationship_uri + "/slideMaster"
  })
  guard main_links is [link] else {
    @failure.reject("protected-content", "Unknown master catalog relationship")
  }
  let mut used = false
  for incoming in links {
    if incoming.owner == link.owner && incoming.id == link.id {
      continue
    }
    let page = self.slides
      .iter()
      .find_first(slide => slide.tree.part == incoming.owner)
    guard page is Some(page) &&
      page.read_only.is_empty() &&
      incoming.kind == relationship_uri + "/slideLayout" &&
      slide_layout(self.opc, incoming.owner, self.parts) ==
      Some(incoming.target) &&
      page.tree.document
      .nodes()
      .all(node => {
        !node.attributes.any(a => {
          a.uri == relationship_uri && a.value == incoming.id
        })
      }) else {
      @failure.reject(
        "protected-content", "Unknown reference to the master or its layouts",
      )
    }
    used = true
  }
  if used {
    let replacement = self
      .master_choices()
      .iter()
      .find_first(pair => pair.0.part != part)
      .unwrap().0.part
    guard self.layout_choices().any(choice => choice.master.part == replacement) else {
      @failure.reject("invalid-layout", "Replacement master has no layouts")
    }
  }
  let list = self.main.required(
    self.main.root("presentation").id,
    "sldMasterIdLst",
    uri=presentation_uri,
  )
  let nodes = self.main.document
    .nodes()
    .filter(node => {
      node.attributes.any(a => a.uri == relationship_uri && a.value == link.id)
    })
  guard nodes is [node] &&
    node.parent == list.id &&
    node.uri == presentation_uri &&
    node.name == "sldMasterId" else {
    @failure.reject(
      "protected-content", "Unknown reference to the master relationship",
    )
  }
  (paths, node, link.id)
}

///|
fn Session::delete_master(
  self : Session,
  part : String,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let (paths, node, id) = self.master_deletion(part)
  let parts = self.parts.copy()
  let removed : Map[String, @xml.Document] = Map([])
  for path in paths {
    removed[path] = self.part_document(path)
    parts.remove(path)
  }
  let (document, edit) = self.main.document.edit_source([
    remove_slide_node(self.main, node),
  ])
  let main = Tree::new(self.main.part, document)
  let edits = [(main.part, edit)]
  for path in [relationship_part(main.part), "[Content_Types].xml"] {
    let original = self.part_document(path)
    let tree = Tree::new(path, original)
    let changes = original
      .nodes()
      .filter(node => {
        if path == "[Content_Types].xml" {
          node.name == "Override" &&
          node
          .attribute("PartName")
          .map(value => {
            value.has_prefix("/") &&
            paths.any(name => name.to_lower() == value[1:].to_owned().to_lower())
          })
          .unwrap_or(false)
        } else {
          node.name == "Relationship" && node.attribute("Id") == Some(id)
        }
      })
      .map(node => remove_slide_node(tree, node))
    let (document, edit) = original.edit_source(changes.iter().collect())
    parts[path] = document
    edits.push((path, edit))
  }
  let after = if paths.contains(self.selection.slide) {
    {
      slide: self.last_slide,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    }
  } else {
    self.selection
  }
  let removed_parts = [
    ..self.removed,
    ..paths.filter(path => self.opc.names.contains(path.to_lower())),
  ]
  let slides = self.rebind_master_slides(
    part, paths, parts, edits, probe, profile,
  )
  self.validate_source_target(
    after.slide,
    parts,
    main~,
    slides~,
    removed=removed_parts,
  )
  self.commit_slides(main, slides, edits, after, parts~, removed~)
  self.query()
}
