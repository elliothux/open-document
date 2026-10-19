///|
fn Session::layout_identity(
  self : Session,
) -> (String, String, Int64) raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  for (tree, _) in self.master_choices() {
    for node in tree.document.nodes() {
      if node.uri == presentation_uri && node.name == "sldLayoutId" {
        reserved[number(
          node.attribute("id").unwrap_or(""),
          2147483648,
          4294967295,
        )
        .to_int64()
        .to_string()] = true
      }
    }
  }
  let segments = self.main.part.split("/").map(v => v.to_owned()).to_array()
  ignore(segments.pop())
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let mut next = self.layout_sequence
  let links = self.relationships()
  while next <= 4294967295L {
    let part = prefix + "slideLayouts/layout\{next}.xml"
    let link = "odLayout\{next}"
    if !reserved.contains(next.to_string()) &&
      !self.opc.names.contains(part.to_lower()) &&
      !self.opc.names.contains(relationship_part(part).to_lower()) &&
      !self.parts
      .keys()
      .any(path => {
        [part.to_lower(), relationship_part(part).to_lower()].contains(
          path.to_lower(),
        )
      }) &&
      !links.any(rel => rel.id == link) {
      return (part, link, next)
    }
    next += 1
  }
  @failure.reject("limit-exceeded", "Layout identities exhausted")
}

///|
fn layout_catalog_change(
  tree : Tree,
  entry : String,
  after : String,
) -> @xml.SourceChange raise @failure.Failure {
  let root = tree.root("sldMaster")
  if tree.one(root.id, "sldLayoutIdLst", uri=presentation_uri) is Some(list) {
    if !after.is_empty() &&
      tree
      .all(list.id, "sldLayoutId", uri=presentation_uri)
      .iter()
      .find_first(node => {
        node.attribute("id", uri=relationship_uri) == Some(after)
      })
      is Some(node) {
      return {
        node: list.id,
        offset: node.end - list.start,
        length: 0,
        xml: entry,
      }
    }
    return insertion(list, entry)
  }
  let markup = "<p:sldLayoutIdLst xmlns:p=\"\{presentation_uri}\">\{entry}</p:sldLayoutIdLst>"
  if tree.children
    .get(root.id)
    .unwrap_or([])
    .iter()
    .find_first(node => {
      node.uri == presentation_uri &&
      ["transition", "timing", "hf", "txStyles", "extLst"].contains(node.name)
    })
    is Some(node) {
    { node: root.id, offset: node.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
}

///|
fn Session::add_layout(
  self : Session,
  source : String,
  copy~ : Bool = false,
) -> Json raise @failure.Failure {
  let choice = self.source_choice(source)
  guard self.layout_choices().length() < 256 else {
    @failure.reject("limit-exceeded", "Slide layout catalog exceeds budget")
  }
  let master = load_tree(self.opc, self.cache, choice.master, parts=self.parts)
  if copy {
    guard choice.kind == "layout" else {
      @failure.reject("invalid-slide", "Select a layout source to copy")
    }
    self.check_layout_copy(choice.tree)
  }
  let (part, link, identity) = self.layout_identity()
  let mut next_object = self.object_sequence
  let document = if copy {
    let (document, next) = copy_slide_objects(
      choice.tree,
      part,
      self.reserved_object_identities(),
      self.object_sequence,
      self.budget,
    )
    next_object = next
    document
  } else {
    @xml.Document::parse(
      @utf8.encode(
        "<p:sldLayout xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" type=\"blank\" preserve=\"1\"><p:cSld>\{empty_shape_tree()}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>",
      ),
      part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  }
  let relations = if copy {
    self
    .copy_slide_relationships(source, part, Map([(source, part)]), [
      "slideMaster", "image", "hyperlink", "slide",
    ])
    .unwrap()
  } else {
    @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"master\" Type=\"\{relationship_uri}/slideMaster\" Target=\"/\{xml_attribute(master.part)}\"/></Relationships>",
      ),
      relationship_part(part),
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  }
  let parts = self.parts.copy()
  let created_parts = Map([
    (part, document),
    (relationship_part(part), relations),
  ])
  for name, value in created_parts {
    parts[name] = value
  }
  let edits : Array[(String, @xml.Edit)] = []
  let previous = if choice.kind == "layout" {
    self
    .relationships()
    .iter()
    .find_first(rel => {
      rel.owner == master.part &&
      !rel.external &&
      rel.target == source &&
      rel.kind == relationship_uri + "/slideLayout"
    })
    .unwrap().id
  } else {
    ""
  }
  let entry = "<p:sldLayoutId xmlns:p=\"\{presentation_uri}\" xmlns:r=\"\{relationship_uri}\" id=\"\{identity}\" r:id=\"\{link}\"/>"
  let (document, edit) = master.document.edit_source([
    layout_catalog_change(master, entry, previous),
  ])
  parts[master.part] = document
  edits.push((master.part, edit))
  for
    (path, markup) in [
      (
        relationship_part(master.part),
        "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/slideLayout\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>",
      ),
    ] {
    let original = self.part_document(path)
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
  self.validate_source_target(part, parts)
  self.commit_slides(
    self.main,
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
    created_parts~,
  )
  self.layout_sequence = identity + 1
  self.object_sequence = next_object
  self.query()
}
