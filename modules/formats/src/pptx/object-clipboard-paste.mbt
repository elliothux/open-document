///|
/// Pastes detached native objects and their bounded resources as one source/resource history entry.
pub fn Session::paste_object_fragment(
  self : Session,
  revision : Int,
  value : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let original = self.current()
  guard original.read_only.is_empty() else {
    @failure.reject("protected-content", original.read_only)
  }
  let fragment = read_object_fragment(value, self.budget)
  let (document, next) = copy_slide_objects(
    fragment.tree,
    original.tree.part,
    self.reserved_object_identities(),
    self.object_sequence,
    self.budget,
  )
  let before = fragment.tree.document
    .nodes()
    .filter(n => n.uri == presentation_uri && n.name == "cNvPr")
  let after = document
    .nodes()
    .filter(n => n.uri == presentation_uri && n.name == "cNvPr")
  let identities : Map[String, String] = Map([])
  for index, node in before {
    identities[source_identity(node.attribute("id").unwrap_or(""))] = source_identity(
      after[index].attribute("id").unwrap_or(""),
    )
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  let created : Map[String, @xml.Document] = Map([])
  let created_media : Map[String, Bytes] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let links = self.relationships()
  let remap : Map[String, String] = Map([])
  let id = identities[fragment.active]
  let paths = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(paths.pop())
  let directory = if paths.is_empty() { "" } else { paths.join("/") + "/" }
  let reserved : Set[String] = Set(
    links.filter(r => r.owner == original.tree.part).map(r => r.id),
  )
  for resource in fragment.resources {
    if resource.image is None {
      remap[resource.id] = self.hyperlink_relationship(
        original.tree.part,
        "external",
        resource.target,
        links,
        parts,
        created,
        edits,
      )
      continue
    }
    let bytes = resource.image.unwrap()
    let (extension, content_type, _, _) = @image.type_info(bytes)
    let mut sequence = 1
    let mut path = ""
    let mut link = ""
    while true {
      path = directory +
        "media/image" +
        id +
        "_clip" +
        sequence.to_string() +
        "." +
        extension
      link = "odObject" + id + "_" + sequence.to_string()
      if !self.opc.names.contains(path.to_lower()) &&
        !parts.contains(path) &&
        !media.contains(path) &&
        !reserved.contains(link) {
        break
      }
      sequence += 1
      guard sequence <= 16384 else {
        @failure.reject(
          "limit-exceeded", "Clipboard image identities exhausted",
        )
      }
    }
    reserved.add(link)
    media[path] = bytes
    created_media[path] = bytes
    remap[resource.id] = link
    self.append_chart_xml(
      relationship_part(original.tree.part),
      "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{link}' Type='\{relationship_uri}/image' Target='/\{xml_attribute(path)}'/>",
      parts,
      created,
      edits,
    )
    self.append_chart_xml(
      "[Content_Types].xml",
      "<Override xmlns='http://schemas.openxmlformats.org/package/2006/content-types' PartName='/\{xml_attribute(path)}' ContentType='\{content_type}'/>",
      parts,
      created,
      edits,
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for node in document.nodes() {
    for attr in node.attributes {
      if attr.uri == relationship_uri && !attr.value.is_empty() {
        changes.push({
          node: node.id,
          offset: attr.start - node.start,
          length: attr.end - attr.start,
          xml: remap[attr.value],
        })
      }
    }
  }
  let bound = if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
  let tree = Tree::new(original.tree.part, bound)
  let markup = tree.children
    .get(bound.nodes()[0].id)
    .unwrap_or([])
    .map(node => tree.standalone_markup(bound, node.id))
    .join("")
  let (document, edit) = original.tree.document.edit_source([
    object_insertion(original.tree, markup),
  ])
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    index=self.source_index(original.tree.part),
    parts~,
    date_time=self.date_time,
  )
  let objects = fragment.selection.map(old => {
    original.tree.part + "#" + identities[old]
  })
  let all = identities
    .values()
    .map(id => original.tree.part + "#" + id)
    .to_array()
  let mut decoded = 0L
  for key in candidate.image_keys() {
    let bytes = media.get(key).unwrap_or_else(() => self.image_content(key))
    let (_, _, width, height) = @image.type_info(bytes)
    decoded += width.to_int64() * height.to_int64() * 4
  }
  guard decoded <= 16777216L else {
    @failure.reject(
      "limit-exceeded", "Pasted slide images exceed decoded budget",
    )
  }
  for id in all {
    let object = candidate.object(id)
    check_clipboard_object(object)
    for paragraph in object.paragraphs {
      let tabs = read_paragraph_tabs(
        paragraph.source.child("pPr").map(p => [p]).unwrap_or([]),
      )
      guard tabs == paragraph.tabs else {
        @failure.reject(
          "protected-content", "Target inherited tabs prevent preserving copied object formatting",
        )
      }
    }
    if object.kind != "group" {
      let (_, _, problem) = fit_text(
        object,
        object.geometry.unwrap(),
        probe,
        profile,
      )
      guard problem.is_empty() else {
        @failure.reject("layout-overflow", problem)
      }
    }
  }
  edits.push((original.tree.part, edit))
  self.commit_page(
    candidate,
    edits,
    {
      slide: original.tree.part,
      objects,
      object: original.tree.part + "#" + identities[fragment.active],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    parts~,
    media~,
    created_parts=created,
    created_media~,
    probe~,
    profile~,
  )
  self.object_sequence = next
  self.query()
}
