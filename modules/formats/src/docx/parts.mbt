///|
fn Session::part_xml(
  self : Session,
  name : String,
) -> @xml.Document raise @failure.Failure {
  ignore(self.document())
  if name == self.main {
    return self.document()
  }
  match self.parts.get(name) {
    Some(document) => document
    None => self.opc.xml(name)
  }
}

///|
fn Session::replacements(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  media~ : Map[String, Bytes] = self.media,
) -> Map[String, Bytes] {
  let replacements = media.copy()
  for name, document in parts {
    if !document.is_original() || !self.opc.names.contains(name.to_lower()) {
      replacements[name] = document.bytes()
    }
  }
  if !document.is_original() {
    replacements[self.main] = document.bytes()
  }
  replacements
}

///|
fn Session::relationships(
  self : Session,
) -> ReadOnlyArray[@opc.Relationship] raise @failure.Failure {
  ignore(self.document())
  let replacements = self.media.copy()
  for name, document in self.parts {
    let added = !self.opc.names.contains(name.to_lower())
    if added ||
      (
        !document.is_original() &&
        (name.to_lower().has_suffix(".rels") || name == "[Content_Types].xml")
      ) {
      replacements[name] = document.bytes()
    }
  }
  self.opc.relationships(replacements~)
}

///|
fn append_part_xml(
  document : @xml.Document,
  markup : String,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let root = document.nodes()[0]
  let change : @xml.SourceChange = if root.empty {
    {
      node: root.id,
      offset: root.opening_end - root.start - 2,
      length: 1,
      xml: ">" + markup + "</" + root.qualified,
    }
  } else {
    {
      node: root.id,
      offset: root.closing_start - root.start,
      length: 0,
      xml: markup,
    }
  }
  document.edit_source([change])
}

///|
fn xml_part_edit_bytes(
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> Int raise @failure.Failure {
  let mut bytes = 0
  for _, steps in edits {
    for edit in steps {
      let count = edit_bytes(edit)
      guard count <= history_byte_limit - bytes else {
        @failure.reject(
          "limit-exceeded", "XML part edit exceeds history budget",
        )
      }
      bytes += count
    }
  }
  for _, document in created {
    let count = document.source().length() * 2
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "XML part edit exceeds history budget")
    }
    bytes += count
  }
  bytes
}
