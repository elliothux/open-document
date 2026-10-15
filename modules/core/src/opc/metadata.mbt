///|
fn read_metadata(
  names : Map[String, String],
  budget : @archive.Budget,
  read : (String) -> Bytes raise @failure.Failure,
) -> (Map[String, String], Array[Relationship], Bool) raise @failure.Failure {
  let mut signed = names.keys().any(key => key.has_prefix("_xmlsignatures/"))
  guard names.contains("[content_types].xml") else {
    @failure.reject("malformed-opc", "Missing content types")
  }
  let types_xml = @xml.Document::parse(
    read(names["[content_types].xml"]),
    "[Content_Types].xml",
    budget.xml_depth,
    budget.entry_bytes,
  )
  let nodes = types_xml.nodes()
  let ns = "http://schemas.openxmlformats.org/package/2006/content-types"
  guard nodes[0].name == "Types" && nodes[0].uri == ns else {
    @failure.reject("malformed-opc", "Invalid content types root")
  }
  let defaults : Map[String, String] = Map([])
  let overrides : Map[String, String] = Map([])
  for node in nodes {
    if node.parent != 0 {
      continue
    }
    guard node.uri == ns else {
      @failure.reject("malformed-opc", "Invalid content type namespace")
    }
    guard node.attribute("ContentType") is Some(content_type) &&
      !content_type.is_empty() else {
      @failure.reject("malformed-opc", "Missing content type")
    }
    if node.name == "Default" {
      guard node.attribute("Extension") is Some(extension) &&
        !extension.is_empty() &&
        !defaults.contains(extension.to_lower()) else {
        @failure.reject("malformed-opc", "Missing or duplicate extension")
      }
      defaults[extension.to_lower()] = content_type
    } else if node.name == "Override" {
      guard node.attribute("PartName") is Some(name) && name.has_prefix("/") else {
        @failure.reject("malformed-opc", "Invalid override name")
      }
      let name = name[1:].to_owned()
      part_name(name)
      guard names.contains(name.to_lower()) &&
        !overrides.contains(name.to_lower()) else {
        @failure.reject(
          "malformed-opc",
          "Missing or duplicate override part",
          part=name,
        )
      }
      overrides[name.to_lower()] = content_type
    } else {
      @failure.reject("malformed-opc", "Unknown content types element")
    }
  }
  let types : Map[String, String] = Map([])
  for key, name in names {
    if key == "[content_types].xml" {
      continue
    }
    let extension = name.split(".").last().unwrap_or("").to_lower().to_owned()
    let content_type = match overrides.get(key) {
      Some(value) => Some(value)
      None => defaults.get(extension)
    }
    guard content_type is Some(content_type) else {
      @failure.reject("malformed-opc", "Part has no content type", part=name)
    }
    types[key] = content_type
    if content_type.has_prefix(
        "application/vnd.openxmlformats-package.digital-signature-",
      ) {
      signed = true
    }
  }
  let relationships : Array[Relationship] = []
  for key, name in names {
    if !key.has_suffix(".rels") {
      continue
    }
    let owner = if key == "_rels/.rels" {
      ""
    } else {
      let segments = name.split("/").collect()
      guard segments.length() >= 2 && segments[segments.length() - 2] == "_rels" else {
        @failure.reject(
          "malformed-opc",
          "Invalid relationships part name",
          part=name,
        )
      }
      let leaf = segments.pop().unwrap()
      ignore(segments.pop())
      segments.push(leaf[:leaf.length() - 5].to_owned())
      let owner = segments.join("/")
      guard names.get(owner.to_lower()) is Some(actual) else {
        @failure.reject(
          "malformed-opc",
          "Relationships owner is missing",
          part=name,
        )
      }
      actual
    }
    let document = @xml.Document::parse(
      read(name),
      name,
      budget.xml_depth,
      budget.entry_bytes,
    )
    let nodes = document.nodes()
    let ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    guard nodes[0].name == "Relationships" && nodes[0].uri == ns else {
      @failure.reject("malformed-opc", "Invalid relationships root", part=name)
    }
    let ids : Map[String, Bool] = Map([])
    for node in nodes {
      if node.parent != 0 {
        continue
      }
      guard node.name == "Relationship" && node.uri == ns else {
        @failure.reject(
          "malformed-opc",
          "Invalid relationship element",
          part=name,
        )
      }
      guard node.attribute("Id") is Some(id) &&
        !id.is_empty() &&
        !ids.contains(id) &&
        node.attribute("Type") is Some(kind) &&
        !kind.is_empty() &&
        node.attribute("Target") is Some(target) else {
        @failure.reject(
          "malformed-opc",
          "Missing relationship attribute or duplicate ID",
          part=name,
        )
      }
      ids[id] = true
      let mode = node.attribute("TargetMode").unwrap_or("Internal")
      guard mode == "Internal" || mode == "External" else {
        @failure.reject("malformed-opc", "Invalid TargetMode", part=name)
      }
      let external = mode == "External"
      let resolved = if external {
        target
      } else {
        resolve_target(owner, target)
      }
      let target = if external {
        resolved
      } else {
        guard names.get(resolved.to_lower()) is Some(actual) else {
          @failure.reject("malformed-opc", "Dangling relationship", part=name)
        }
        actual
      }
      if kind.has_prefix(
          "http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/",
        ) {
        signed = true
      }
      relationships.push({ owner, id, kind, target, external, })
    }
  }
  (types, relationships, signed)
}
