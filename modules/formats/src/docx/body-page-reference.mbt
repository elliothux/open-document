///|
fn WordTree::check_body_field_target(
  self : WordTree,
  code : String,
) -> Unit raise @failure.Failure {
  if !code.has_prefix("PAGEREF:") {
    return
  }
  let name = code.split(":").to_array()[1].to_owned().to_lower()
  guard self
    .bookmarks()
    .any(bookmark => {
      bookmark.name.to_lower() == name && bookmark.reason.is_empty()
    }) else {
    @failure.reject(
      "invalid-operation", "Select an available bookmark for the page reference",
    )
  }
}

///|
fn WordTree::page_reference_renames(
  self : WordTree,
  name : String,
  replacement : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  for id in self.order {
    let node = self.nodes[id]
    if node.uri != word_uri || node.name != "fldSimple" {
      continue
    }
    let attribute = node.attributes
      .iter()
      .find_first(a => a.uri == word_uri && a.name == "instr")
    guard attribute is Some(attribute) else { continue }
    let code = running_field_code(attribute.value) catch {
      @failure.Failure(..) => ""
    }
    if !code.has_prefix("PAGEREF:") ||
      code.split(":").to_array()[1].to_owned().to_lower() != name.to_lower() {
      continue
    }
    self.check_editable_paragraph(
      node.parent,
      part="",
      pictures=true,
      fields=true,
    )
    let mut offset = 0
    let instruction = attribute.value
    while offset < instruction.length() &&
          [32, 9].contains(instruction[offset].to_int()) {
      offset += 1
    }
    while offset < instruction.length() &&
          ![32, 9].contains(instruction[offset].to_int()) {
      offset += 1
    }
    while offset < instruction.length() &&
          [32, 9].contains(instruction[offset].to_int()) {
      offset += 1
    }
    let start = offset
    while offset < instruction.length() &&
          ![32, 9].contains(instruction[offset].to_int()) {
      offset += 1
    }
    changes.push({
      node: id,
      offset: attribute.start - node.start,
      length: attribute.end - attribute.start,
      xml: property_attribute(
        instruction[:start].to_owned() +
        replacement +
        instruction[offset:].to_owned(),
      ),
    })
    guard changes.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Page reference updates exceed limits")
    }
  }
  changes
}
