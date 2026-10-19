///|
fn Session::add_master(
  self : Session,
  source : String,
  copy~ : Bool = false,
) -> Json raise @failure.Failure {
  let sources = self.master_creation_sources(source, copy)
  let choice = self.source_choice(source)
  let (part, theme_part, link, identity) = self.master_identity()
  let links = self.relationships()
  let remapped : Map[String, String] = Map([])
  let layout_ids : Map[String, Int64] = Map([])
  let layout_parts : Array[(String, Int64)] = []
  let mut next_layout = self.layout_sequence
  let mut next_object = self.object_sequence
  if copy {
    remapped[choice.master] = part
    remapped[sources.last().unwrap().part] = theme_part
  }
  let layouts = if copy {
    sources
    .filter(tree => tree.document.nodes()[0].name == "sldLayout")
    .map(tree => tree.part)
  } else {
    [""]
  }
  let identities = self.layout_identities(layouts.length())
  for index, original in layouts {
    let (target, _, number) = identities[index]
    next_layout = number + 1
    layout_parts.push((target, number))
    if copy {
      remapped[original] = target
      layout_ids[original] = number
    }
  }
  let created : Map[String, @xml.Document] = Map([])
  let reserved = self.reserved_object_identities()
  if copy {
    for tree in sources {
      let target = remapped[tree.part]
      let (document, next) = copy_slide_objects(
        tree,
        target,
        reserved,
        next_object,
        self.budget,
      )
      next_object = next
      let root = document.nodes()[0].name
      let document = if root == "sldMaster" {
        let copied = Tree::new(target, document)
        let changes = document
          .nodes()
          .filter(node => {
            node.uri == presentation_uri && node.name == "sldLayoutId"
          })
          .map(node => {
            let id = node.attribute("id", uri=relationship_uri).unwrap_or("")
            let old = links
              .iter()
              .find_first(link => link.owner == tree.part && link.id == id)
              .unwrap().target
            attribute_change(
              { tree: copied, node, },
              "id",
              layout_ids[old].to_string(),
            )
          })
        if changes.is_empty() {
          document
        } else {
          document.edit_source(changes.iter().collect()).0
        }
      } else {
        document
      }
      created[target] = document
      let allowed = match root {
        "sldMaster" => ["slideLayout", "theme", "image", "hyperlink", "slide"]
        "sldLayout" => ["slideMaster", "image", "hyperlink", "slide"]
        _ => ["image", "hyperlink"]
      }
      if self.copy_slide_relationships(
          tree.part,
          target,
          remapped,
          allowed,
          links~,
        )
        is Some(relations) {
        created[relationship_part(target)] = relations
      }
    }
  } else {
    let (layout, layout_id) = layout_parts[0]
    let entry = "<p:sldLayoutId xmlns:p=\"\{presentation_uri}\" xmlns:r=\"\{relationship_uri}\" id=\"\{layout_id}\" r:id=\"layout\"/>"
    for
      (path, xml) in [
        (part, blank_master(entry)),
        (theme_part, blank_theme()),
        (layout, blank_layout()),
        (
          relationship_part(part),
          "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"layout\" Type=\"\{relationship_uri}/slideLayout\" Target=\"/\{xml_attribute(layout)}\"/><Relationship Id=\"theme\" Type=\"\{relationship_uri}/theme\" Target=\"/\{xml_attribute(theme_part)}\"/></Relationships>",
        ),
        (
          relationship_part(layout),
          "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"master\" Type=\"\{relationship_uri}/slideMaster\" Target=\"/\{xml_attribute(part)}\"/></Relationships>",
        ),
      ] {
      created[path] = @xml.Document::parse(
        @utf8.encode(xml),
        path,
        self.budget.xml_depth,
        self.budget.entry_bytes,
      )
    }
  }
  let master_link = links
    .iter()
    .find_first(link => {
      link.owner == self.main.part &&
      link.target == choice.master &&
      link.kind == relationship_uri + "/slideMaster"
    })
    .unwrap().id
  let list = self.main.required(
    self.main.root("presentation").id,
    "sldMasterIdLst",
    uri=presentation_uri,
  )
  let node = self.main
    .all(list.id, "sldMasterId", uri=presentation_uri)
    .iter()
    .find_first(node => {
      node.attribute("id", uri=relationship_uri) == Some(master_link)
    })
    .unwrap()
  let (document, edit) = self.main.document.edit_source([
    {
      node: list.id,
      offset: node.end - list.start,
      length: 0,
      xml: "<p:sldMasterId xmlns:p=\"\{presentation_uri}\" xmlns:r=\"\{relationship_uri}\" id=\"\{identity}\" r:id=\"\{link}\"/>",
    },
  ])
  let main = Tree::new(self.main.part, document)
  let edits = [(main.part, edit)]
  let parts = self.parts.copy()
  for path, document in created {
    parts[path] = document
  }
  let overrides = StringBuilder()
  for path, document in created {
    let root = document.nodes()[0]
    let kind = match root.name {
      "sldMaster" =>
        "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"
      "sldLayout" =>
        "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"
      "theme" => "application/vnd.openxmlformats-officedocument.theme+xml"
      _ => continue
    }
    overrides.write_string(
      "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(path)}\" ContentType=\"\{kind}\"/>",
    )
  }
  for
    (path, xml) in [
      ("[Content_Types].xml", overrides.to_string()),
      (
        relationship_part(main.part),
        "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/slideMaster\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
    ] {
    let original = self.part_document(path)
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], xml),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
  self.validate_created_sources(main, parts, created)
  self.commit_slides(
    main,
    self.slides,
    edits,
    {
      slide: part,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    parts~,
    created_parts=created,
  )
  self.master_sequence = identity + 1
  self.layout_sequence = next_layout
  self.object_sequence = next_object
  self.query()
}
