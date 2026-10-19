///|
fn relationship_part(owner : String) -> String {
  let segments = owner.split("/").map(segment => segment.to_owned()).to_array()
  let leaf = segments.pop().unwrap()
  segments.push("_rels")
  segments.push(leaf + ".rels")
  segments.join("/")
}

///|
fn slide_layout(
  opc : @opc.Package,
  owner : String,
  parts : Map[String, @xml.Document],
) -> String? raise @failure.Failure {
  let layout = relation(opc, owner, "slideLayout", parts~)
  guard layout is Some(_) || !parts.contains(relationship_part(owner)) else {
    @failure.reject(
      "malformed-pptx",
      "Invalid slide layout relationship",
      part=owner,
    )
  }
  layout
}

///|
fn image_target(
  opc : @opc.Package,
  owner : String,
  id : String,
  parts : Map[String, @xml.Document],
) -> String? raise @failure.Failure {
  if parts.get(relationship_part(owner)) is Some(document) {
    let root = document.nodes()[0]
    let links = document
      .nodes()
      .filter(node => node.parent == root.id && node.attribute("Id") == Some(id))
    guard links is [link] &&
      link.attribute("Type") == Some(relationship_uri + "/image") &&
      link.attribute("TargetMode") != Some("External") &&
      link.attribute("Target") is Some(target) else {
      return None
    }
    return Some(@opc.resolve_target(owner, target))
  }
  opc
  .relationships()
  .iter()
  .find_first(rel => {
    rel.owner == owner &&
    rel.id == id &&
    rel.kind == relationship_uri + "/image" &&
    !rel.external
  })
  .map(rel => rel.target)
}

///|
fn Session::replacements(
  self : Session,
  main : Tree,
  slides : Array[Slide],
  parts : Map[String, @xml.Document],
  media~ : Map[String, Bytes] = self.media,
) -> Map[String, Bytes] {
  let replacements : Map[String, Bytes] = Map([])
  // Restoring created resources must preserve the saved ZIP order across undo/redo.
  let names = parts.keys().to_array()
  names.append(media.keys().to_array())
  names.sort()
  for part in names {
    if media.get(part) is Some(bytes) {
      replacements[part] = bytes
      continue
    }
    let document = parts[part]
    if !document.is_original() || !self.opc.names.contains(part.to_lower()) {
      replacements[part] = document.bytes()
    }
  }
  if !main.document.is_original() {
    replacements[main.part] = main.document.bytes()
  }
  for slide in slides {
    if !slide.tree.document.is_original() ||
      !self.opc.names.contains(slide.tree.part.to_lower()) {
      replacements[slide.tree.part] = slide.tree.document.bytes()
    }
  }
  replacements
}

///|
fn image_content_type(
  opc : @opc.Package,
  part : String,
  parts : Map[String, @xml.Document],
) -> String? raise @failure.Failure {
  if parts.get("[Content_Types].xml") is Some(document) {
    for node in document.nodes() {
      if node.name == "Override" &&
        node.attribute("PartName") == Some("/" + part) {
        return node.attribute("ContentType")
      }
    }
  }
  opc.content_type(part)
}

///|
fn Session::relationships(
  self : Session,
) -> ReadOnlyArray[@opc.Relationship] raise @failure.Failure {
  self.opc.relationships(
    replacements=self.replacements(self.main, self.slides, self.parts),
    removed=self.removed,
  )
}
