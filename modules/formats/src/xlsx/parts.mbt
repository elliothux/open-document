///|
fn Session::part_xml(
  self : Session,
  part : String,
) -> @xml.Document raise @failure.Failure {
  self.parts.get(part).unwrap_or_else(() => self.opc.xml(part))
}

///|
fn Session::replacements(
  self : Session,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  parts : Map[String, @xml.Document],
  media~ : Map[String, Bytes] = self.media,
) -> Map[String, Bytes] {
  let replacements : Map[String, Bytes] = Map([])
  // Restoring deleted new parts must not change their ZIP entry order.
  let names = parts.keys().to_array()
  names.sort()
  for part in names {
    let document = parts[part]
    if !document.is_original() || !self.opc.names.contains(part.to_lower()) {
      replacements[part] = document.bytes()
    }
  }
  if !workbook.is_original() {
    replacements[self.main] = workbook.bytes()
  }
  for sheet in sheets {
    if !sheet.document.is_original() ||
      !self.opc.names.contains(sheet.id.to_lower()) {
      replacements[sheet.id] = sheet.document.bytes()
    }
  }
  let names = media.keys().to_array()
  names.sort()
  for part in names {
    replacements[part] = media[part]
  }
  replacements
}

///|
fn Session::relationships(
  self : Session,
) -> ReadOnlyArray[@opc.Relationship] raise @failure.Failure {
  let cache = self.read_cache()
  if cache.relationships is Some(relationships) {
    return relationships
  }
  let changes_metadata = name => self.opc.changes_metadata(name)
  let relationships = if !self.removed.is_empty() ||
    self.parts.keys().any(changes_metadata) ||
    self.media.keys().any(changes_metadata) ||
    changes_metadata(self.main) ||
    self.sheets.iter().any(sheet => changes_metadata(sheet.id)) {
    self.opc.relationships(
      replacements=self.replacements(self.sheets, self.workbook, self.parts),
      removed=self.removed,
    )
  } else {
    self.opc.relationships()
  }
  cache.relationships = Some(relationships)
  relationships
}
