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
  replacements
}

///|
fn Session::relationships(
  self : Session,
) -> ReadOnlyArray[@opc.Relationship] raise @failure.Failure {
  self.opc.relationships(
    replacements=self.replacements(self.sheets, self.workbook, self.parts),
    removed=self.removed,
  )
}
