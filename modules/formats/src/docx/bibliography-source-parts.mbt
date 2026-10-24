///|
fn Session::create_source_part(
  self : Session,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  uri~ : String = bibliography_uri,
) -> (String, @xml.Document) raise @failure.Failure {
  let relationship_uri = "http://schemas.openxmlformats.org/package/2006/relationships"
  let properties_uri = "http://schemas.openxmlformats.org/officeDocument/2006/customXml"
  let reserved : Set[String] = Set([])
  let links = self.relationships()
  let props = links.filter(link => {
    !link.external && link.kind == custom_xml_relationship + "Props"
  })
  guard props.length() <= 64 else {
    @failure.reject("limit-exceeded", "Too many custom XML property parts")
  }
  for link in props {
    for node in self.part_xml(link.target).nodes() {
      if node.attribute("itemID", uri=properties_uri) is Some(id) {
        reserved.add(id.to_upper())
      }
    }
  }
  let (item, property, relation, guid) = for index in 1..<=16384 {
    let item = "customXml/item" + index.to_string() + ".xml"
    let property = "customXml/itemProps" + index.to_string() + ".xml"
    let relation = "customXml/_rels/item" + index.to_string() + ".xml.rels"
    let digits = index.to_string()
    let guid = "{00000000-0000-4000-8000-" +
      "0".repeat(12 - digits.length()) +
      digits +
      "}"
    if [item, property, relation].all(name => {
        !self.opc.names.contains(name.to_lower()) && !parts.contains(name)
      }) &&
      !reserved.contains(guid) {
      break (item, property, relation, guid)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Custom XML part identities exhausted")
  }
  let root = "<b:Sources xmlns:b=\"\{uri}\"/>"
  for
    (name, xml) in [
      (item, root),
      (
        property,
        "<ds:datastoreItem xmlns:ds=\"\{properties_uri}\" ds:itemID=\"\{guid}\"><ds:schemaRefs><ds:schemaRef ds:uri=\"\{uri}\"/></ds:schemaRefs></ds:datastoreItem>",
      ),
      (
        relation,
        "<Relationships xmlns=\"\{relationship_uri}\"><Relationship Id=\"properties\" Type=\"\{custom_xml_relationship}Props\" Target=\"/\{property}\"/></Relationships>",
      ),
    ] {
    let document = @xml.Document::parse(
      @utf8.encode(xml),
      name,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[name] = document
    created[name] = document
  }
  let segments = self.main.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(value => value.to_owned())
    .join("/")
  let path = (if directory.is_empty() { "" } else { directory + "/" }) +
    "_rels/" +
    segments.last().unwrap().to_owned() +
    ".rels"
  let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
  let used = links.filter(link => link.owner == self.main).map(link => link.id)
  let id = for i in 1..<=65536 {
    let id = "odSource" + i.to_string()
    if !used.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Source relationship identities exhausted",
    )
  }
  let markup = "<Relationship xmlns=\"\{relationship_uri}\" Id=\"\{id}\" Type=\"\{custom_xml_relationship}\" Target=\"/\{item}\"/>"
  let mut added_rels = false
  if self.opc.names.contains(path.to_lower()) || parts.contains(path) {
    let original = parts.get(path).unwrap_or_else(() => self.part_xml(path))
    let (document, step) = append_part_xml(original, markup)
    parts[path] = document
    if created.contains(path) {
      created[path] = document
    } else {
      edits.get_or_init(path, () => []).push(step)
    }
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"\{relationship_uri}\">\{markup}</Relationships>",
      ),
      path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[path] = document
    created[path] = document
    added_rels = true
  }
  let type_uri = "http://schemas.openxmlformats.org/package/2006/content-types"
  let overrides = [
      (item, "application/xml"),
      (
        property, "application/vnd.openxmlformats-officedocument.customXmlProperties+xml",
      ),
      (relation, "application/vnd.openxmlformats-package.relationships+xml"),
      ..if added_rels {
        [(path, "application/vnd.openxmlformats-package.relationships+xml")]
      } else {
        []
      },
    ]
    .map(pair => {
      "<Override xmlns=\"\{type_uri}\" PartName=\"/\{pair.0}\" ContentType=\"\{pair.1}\"/>"
    })
    .join("")
  let types = self.opc.names["[content_types].xml"]
  let original = parts.get(types).unwrap_or_else(() => self.part_xml(types))
  let (document, step) = append_part_xml(original, overrides)
  parts[types] = document
  edits.get_or_init(types, () => []).push(step)
  (item, parts[item])
}

///|
fn Session::source_references(
  self : Session,
) -> Set[String] raise @failure.Failure {
  let result : Set[String] = Set([])
  fn record(code : String) {
    let code = code.trim().to_owned()
    if !code.to_upper().has_prefix("CITATION") {
      return
    }
    if code.length() > 1024 {
      result.add("")
      return
    }
    let tokens = text_reference_tokens(code) catch {
      _ => {
        result.add("")
        return
      }
    }
    guard tokens.get(0).map(token => token.0.to_upper()) == Some("CITATION") else {
      return
    }
    guard tokens.get(1) is Some(tag) else {
      result.add("")
      return
    }
    result.add(tag.0)
    for i in 2..<tokens.length() {
      if !tokens[i].1 && tokens[i].0.to_lower() == "\\m" {
        if tokens.get(i + 1) is Some(tag) {
          result.add(tag.0)
        } else {
          result.add("")
        }
      }
    }
  }
  let mut work = 0
  for name in self.style_part_names() {
    let document = self.part_xml(name)
    let stack : Array[(String, Bool)] = []
    for node in document.nodes() {
      work += 1
      guard work <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Citation ownership scan exceeds budget",
        )
      }
      if node.uri != word_uri {
        continue
      }
      if node.name == "fldSimple" {
        record(node.attribute("instr", uri=word_uri).unwrap_or(""))
      }
      if node.name == "fldChar" {
        match node.attribute("fldCharType", uri=word_uri) {
          Some("begin") => {
            guard stack.length() < 32 else {
              @failure.reject(
                "limit-exceeded", "Citation field nesting exceeds budget",
              )
            }
            stack.push(("", true))
          }
          Some("separate") =>
            if stack.pop() is Some((code, _)) {
              record(code)
              stack.push((code, false))
            }
          Some("end") =>
            if stack.pop() is Some((code, reading)) {
              if reading {
                record(code)
              }
            }
          _ => ()
        }
      }
      if node.name == "instrText" {
        if stack.get(stack.length() - 1) is Some((code, true)) {
          guard code.length() + node.text.length() <= 1024 else {
            result.add("")
            continue
          }
          stack[stack.length() - 1] = (code + node.text, true)
        } else if stack.is_empty() {
          record(node.text)
        }
      }
    }
    for (code, _) in stack {
      if code.to_upper().contains("CITATION") {
        result.add("")
      }
    }
  }
  result
}
