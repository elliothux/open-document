///|
let creation_uri = "http://schemas.microsoft.com/office/powerpoint/2010/main"

///|
fn document_guid(next : Int64) -> String {
  let digits = next.to_string()
  "{00000000-0000-4000-8000-" + "0".repeat(12 - digits.length()) + digits + "}"
}

///|
fn copied_creation_extension(tree : Tree, node : @xml.Node) -> Bool {
  let children = tree.children.get(node.id).unwrap_or([])
  node.uri == presentation_uri &&
  node.name == "ext" &&
  node.attribute("uri") == Some("{BB962C8B-B14F-4D97-AF65-F5344CB8AC3E}") &&
  children is [child] &&
  child.uri == creation_uri &&
  child.name == "creationId" &&
  child.attributes.iter().all(a => a.uri.is_empty() && a.name == "val") &&
  tree.children.get(child.id).unwrap_or([]).is_empty()
}

///|
fn check_slide_copy_markup(tree : Tree) -> Unit raise @failure.Failure {
  for node in tree.document.nodes() {
    let creation = node.uri == creation_uri &&
      node.name == "creationId" &&
      node.parent >= 0 &&
      copied_creation_extension(tree, tree.nodes[node.parent])
    let media = node.uri == creation_uri &&
      node.name == "media" &&
      node.parent >= 0 &&
      media_extension(tree, tree.nodes[node.parent])
    guard (
        [presentation_uri, drawing_uri].contains(node.uri) ||
        creation ||
        media ||
        chart_frame_reference(tree, node)
      ) &&
      node.attributes
      .iter()
      .all(a => {
        a.uri.is_empty() ||
        a.uri == relationship_uri ||
        a.uri == "http://www.w3.org/XML/1998/namespace"
      }) &&
      (
        node.name != "extLst" ||
        tree.children
        .get(node.id)
        .unwrap_or([])
        .all(child => {
          copied_creation_extension(tree, child) || media_extension(tree, child)
        })
      ) else {
      @failure.reject(
        "protected-content",
        "Slide identity extensions require copying support",
        part=tree.part,
      )
    }
    if node.name.has_suffix("Locks") && flag(node, "noCopy") {
      @failure.reject(
        "protected-content",
        "Slide object copying is locked",
        part=tree.part,
      )
    }
  }
}

///|
fn copy_slide_objects(
  tree : Tree,
  part : String,
  reserved : Map[String, Bool],
  first : Int64,
  budget : @archive.Budget,
) -> (@xml.Document, Int64) raise @failure.Failure {
  check_slide_copy_markup(tree)
  let identities : Map[String, String] = Map([])
  let changes : Array[@xml.SourceChange] = []
  let mut next = first
  reserve_drawing_identities(tree.document, reserved)
  for node in tree.document.nodes() {
    let creation = node.uri == creation_uri && node.name == "creationId"
    let field = node.uri == drawing_uri && node.name == "fld"
    if !creation &&
      !field &&
      (node.uri != presentation_uri || node.name != "cNvPr") {
      continue
    }
    let key = if creation { "val" } else { "id" }
    let original = node.attribute(key).unwrap_or("")
    let original = if creation || field {
      original
    } else {
      source_identity(original)
    }
    guard creation || field || !identities.contains(original) else {
      @failure.reject(
        "malformed-pptx",
        "Duplicate copied object identity",
        part=tree.part,
      )
    }
    while reserved.contains(next.to_string()) ||
          (field && reserved.contains(document_guid(next))) {
      next += 1L
    }
    guard next <= 4294967295L else {
      @failure.reject("limit-exceeded", "Copied object identities exhausted")
    }
    if !creation && !field {
      identities[original] = next.to_string()
    }
    reserved[next.to_string()] = true
    let value = if field { document_guid(next) } else { next.to_string() }
    reserved[value] = true
    changes.push(attribute_change({ tree, node, }, key, value))
    next += 1L
  }
  for node in tree.document.nodes() {
    for a in node.attributes {
      if !a.uri.is_empty() ||
        !(["spid", "spId", "shapeId", "shapeIdRef"].contains(a.name) ||
        (
          node.uri == drawing_uri &&
          ["stCxn", "endCxn"].contains(node.name) &&
          a.name == "id"
        )) {
        continue
      }
      guard identities.get(source_identity(a.value)) is Some(value) else {
        @failure.reject(
          "protected-content",
          "Copied object reference has no local target",
          part=tree.part,
        )
      }
      changes.push(attribute_change({ tree, node, }, a.name, value))
    }
  }
  let bytes = if changes.is_empty() {
    tree.document.bytes()
  } else {
    tree.document.edit_source(changes).0.bytes()
  }
  (
    @xml.Document::parse(bytes, part, budget.xml_depth, budget.entry_bytes),
    next,
  )
}

///|
fn Session::copy_slide_relationships(
  self : Session,
  owner : String,
  target : String,
  remapped : Map[String, String],
  allowed : Array[String],
  links? : ReadOnlyArray[@opc.Relationship],
) -> @xml.Document? raise @failure.Failure {
  let path = relationship_part(owner)
  guard self.parts.contains(path) || self.opc.names.contains(path.to_lower()) else {
    return None
  }
  let original = self.part_document(path)
  guard original.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Copied relationships exceed history budget",
    )
  }
  let links = links.unwrap_or_else(() => self.relationships())
  let changes : Array[@xml.SourceChange] = []
  let tree = Tree::new(path, original)
  for node in original.nodes() {
    if node.parent != original.nodes()[0].id {
      continue
    }
    let id = node.attribute("Id").unwrap_or("")
    let link = links
      .iter()
      .find_first(link => link.owner == owner && link.id == id)
      .unwrap()
    guard (
        allowed.any(kind => link.kind == relationship_uri + "/" + kind) ||
        (allowed.contains("media") && link.kind == media_relationship_uri)
      ) &&
      (!link.external || link.kind == relationship_uri + "/hyperlink") else {
      @failure.reject(
        "protected-content",
        "Slide resource ownership requires copying support",
        part=owner,
      )
    }
    if !link.external {
      changes.push(
        attribute_change(
          { tree, node, },
          "Target",
          xml_attribute("/" + remapped.get(link.target).unwrap_or(link.target)),
        ),
      )
    }
  }
  let bytes = if changes.is_empty() {
    original.bytes()
  } else {
    original.edit_source(changes).0.bytes()
  }
  Some(
    @xml.Document::parse(
      bytes,
      relationship_part(target),
      self.budget.xml_depth,
      self.budget.entry_bytes,
    ),
  )
}

///|
fn Session::copy_slide_parts(
  self : Session,
  source : Slide,
  target : String,
  identity : Int64,
) -> (
  @xml.Document,
  Map[String, @xml.Document],
  Map[String, Bytes],
  String,
  Array[(String, @xml.Document, @xml.Edit)],
  Int64,
) raise @failure.Failure {
  guard source.tree.document.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Copied slide exceeds history budget")
  }
  let reserved = self.reserved_object_identities()
  let links = self.relationships()
  for link in links {
    if !link.external && link.kind == relationship_uri + "/notesSlide" {
      reserve_drawing_identities(self.part_document(link.target), reserved)
    }
  }
  let (document, next) = copy_slide_objects(
    source.tree,
    target,
    reserved,
    self.object_sequence,
    self.budget,
  )
  let mut next = next
  let documents : Map[String, @xml.Document] = Map([])
  let workbooks : Map[String, Bytes] = Map([])
  let remapped = Map::from_array([(source.tree.part, target)])
  let metadata : Array[(String, @xml.Document, @xml.Edit)] = []
  let types = StringBuilder()
  let mut bytes = document.source().length().to_int64() * 2
  for
    (kind, directory) in [
      ("notesSlide", "notesSlides"),
      ("comments", "comments"),
    ] {
    let owned = links
      .iter()
      .filter(link => {
        link.owner == source.tree.part &&
        link.kind == relationship_uri + "/" + kind
      })
      .collect()
    guard owned.length() <= 1 else {
      @failure.reject("protected-content", "Multiple slide resource owners")
    }
    if owned.get(0) is Some(link) {
      guard !link.external else {
        @failure.reject(
          "protected-content", "External slide resources cannot be copied",
        )
      }
      let original = self.part_document(link.target)
      bytes += original.source().length().to_int64() * 2
      guard bytes <= 4194304L else {
        @failure.reject(
          "limit-exceeded", "Copied slide resources exceed history budget",
        )
      }
      let tree = Tree::new(link.target, original)
      if kind != "comments" {
        check_slide_copy_markup(tree)
      }
      ignore(tree.root(if kind == "comments" { "cmLst" } else { "notes" }))
      let segments = self.main.part.split("/").map(p => p.to_owned()).to_array()
      ignore(segments.pop())
      let prefix = if segments.is_empty() {
        ""
      } else {
        segments.join("/") + "/"
      }
      let mut sequence = 0
      let mut part = ""
      while true {
        part = prefix + directory + "/odSlide\{identity}-\{sequence}.xml"
        if !self.opc.names.contains(part.to_lower()) &&
          !self.parts.contains(part) &&
          !self.opc.names.contains(relationship_part(part).to_lower()) &&
          !self.parts.contains(relationship_part(part)) {
          break
        }
        sequence += 1
        guard sequence <= self.budget.entries else {
          @failure.reject(
            "limit-exceeded", "Slide resource identity budget exceeded",
          )
        }
      }
      let copied = if kind == "comments" {
        let (comments, edit) = self.copy_slide_comments(tree, part)
        if edit is Some(value) {
          metadata.push(value)
        }
        comments
      } else {
        let (notes, issued) = copy_slide_objects(
          tree,
          part,
          reserved,
          next,
          self.budget,
        )
        next = issued
        notes
      }
      documents[part] = copied
      remapped[link.target] = part
      types.write_string(
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.\{kind}+xml\"/>",
      )
    }
  }
  let resources = remapped.copy()
  let copied_charts : Map[String, Bool] = Map([])
  let mut chart_sequence = 0
  for link in links {
    if link.owner != source.tree.part ||
      link.kind != relationship_uri + "/chart" {
      continue
    }
    guard !link.external else {
      @failure.reject(
        "protected-content", "External slide charts cannot be copied",
      )
    }
    if copied_charts.contains(link.target) {
      continue
    }
    let chart = read_chart_part(self.opc, link.target, self.parts)
    let (part, overrides) = self.copy_chart_parts(
      chart,
      "Slide\{identity}_\{chart_sequence}",
      documents,
      workbooks,
    )
    chart_sequence += 1
    copied_charts[link.target] = true
    resources[link.target] = part
    types.write_string(overrides)
  }
  for original, part in remapped {
    let allowed = if original == source.tree.part {
      [
        "slideLayout", "image", "hyperlink", "slide", "notesSlide", "comments", "audio",
        "video", "media", "chart",
      ]
    } else if documents[part].nodes()[0].name == "notes" {
      ["notesMaster", "image", "hyperlink", "slide"]
    } else {
      ["hyperlink"]
    }
    if self.copy_slide_relationships(original, part, resources, allowed)
      is Some(relations) {
      bytes += relations.source().length().to_int64() * 2
      guard bytes <= 4194304L else {
        @failure.reject(
          "limit-exceeded", "Copied slide relationships exceed history budget",
        )
      }
      documents[relationship_part(part)] = relations
    }
  }
  guard documents.contains(relationship_part(target)) else {
    @failure.reject("malformed-pptx", "Missing source slide relationships")
  }
  (document, documents, workbooks, types.to_string(), metadata, next)
}
