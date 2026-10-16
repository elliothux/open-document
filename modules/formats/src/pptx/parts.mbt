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
  guard parts.get(relationship_part(owner)) is Some(document) else {
    return relation(opc, owner, "slideLayout")
  }
  let root = document.nodes()[0]
  let links = document
    .nodes()
    .filter(node => {
      node.parent == root.id &&
      node.attribute("Type") == Some(relationship_uri + "/slideLayout")
    })
  guard links is [link] &&
    link.attribute("TargetMode") != Some("External") &&
    link.attribute("Target") is Some(target) else {
    @failure.reject(
      "malformed-pptx",
      "Invalid slide layout relationship",
      part=owner,
    )
  }
  Some(@opc.resolve_target(owner, target))
}

///|
fn Session::replacements(
  self : Session,
  main : Tree,
  slides : Array[Slide],
  parts : Map[String, @xml.Document],
) -> Map[String, Bytes] {
  let replacements : Map[String, Bytes] = Map([])
  for part, document in parts {
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
fn Session::relationships(
  self : Session,
) -> ReadOnlyArray[@opc.Relationship] raise @failure.Failure {
  self.opc.relationships(
    replacements=self.replacements(self.main, self.slides, self.parts),
    removed=self.removed,
  )
}
