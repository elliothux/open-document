///|
fn WordTree::valid_numbering_properties(self : WordTree, id : Int32) -> Bool {
  try {
    let node = self.nodes[id]
    let source = self.source[node.start:node.end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      return false
    }
    self.numbering_shape(id, [], ["numId", "ilvl"])
    guard self.children[self.nodes[id].parent]
      .filter(child => {
        self.nodes[child].uri == word_uri && self.nodes[child].name == "numPr"
      })
      .length() ==
      1 else {
      return false
    }
    if self.numbering_value(id, "numId") is Some(value) {
      ignore(numbering_integer(value, 2147483646))
    }
    if self.numbering_value(id, "ilvl") is Some(value) {
      ignore(numbering_integer(value, 8))
    }
    true
  } catch {
    _ => false
  }
}

///|
fn list_properties(instance : Int32, level : Int32) -> String {
  "<od:numPr xmlns:od=\"\{word_uri}\"><od:ilvl od:val=\"\{level}\"/><od:numId od:val=\"\{instance}\"/></od:numPr>"
}

///|
fn NumberingContext::level(
  self : NumberingContext,
  instance : Int32,
  level : Int32,
) -> NumberLevel raise @failure.Failure {
  guard self.definition(instance).levels.get(level) is Some(value) else {
    @failure.reject("invalid-numbering", "Missing numbering level")
  }
  value
}

///|
fn Session::list_identities(
  self : Session,
) -> (Int32, Int32) raise @failure.Failure {
  let instances : Map[Int32, Bool] = Map([])
  let abstracts : Map[Int32, Bool] = Map([])
  for part in self.style_part_names() {
    for node in self.part_xml(part).nodes() {
      if node.uri != word_uri {
        continue
      }
      for (name, target) in [("numId", instances), ("abstractNumId", abstracts)] {
        let value = if node.name == name {
          node.attribute("val", uri=word_uri)
        } else {
          node.attribute(name, uri=word_uri)
        }
        if value is Some(value) {
          let value = @string.parse_int(value[:]) catch { _ => continue }
          if value >= 0 {
            target[value] = true
          }
        }
      }
    }
  }
  let instance = for i = 1; i <= 65536; i = i + 1 {
    if !instances.contains(i) {
      break i
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free list identity")
  }
  let abstract_id = for i = 0; i < 65536; i = i + 1 {
    if !abstracts.contains(i) {
      break i
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free abstract list identity")
  }
  (instance, abstract_id)
}

///|
fn list_definition(
  instance : Int32,
  abstract_id : Int32,
  format : String,
) -> String {
  let output = StringBuilder()
  output.write_string(
    "<od:abstractNum xmlns:od=\"\{word_uri}\" od:abstractNumId=\"\{abstract_id}\"><od:multiLevelType od:val=\"multilevel\"/>",
  )
  for level in 0..<9 {
    let pattern = if format == "bullet" {
      "•"
    } else {
      Array::makei(level + 1, i => "%\{i + 1}").join(".") + "."
    }
    output.write_string(
      "<od:lvl od:ilvl=\"\{level}\"><od:start od:val=\"1\"/><od:numFmt od:val=\"\{format}\"/><od:lvlText od:val=\"\{pattern}\"/><od:lvlJc od:val=\"left\"/><od:suff od:val=\"tab\"/><od:pPr><od:ind od:left=\"\{720 * (level + 1)}\" od:hanging=\"360\"/></od:pPr></od:lvl>",
    )
  }
  output.write_string(
    "</od:abstractNum><od:num xmlns:od=\"\{word_uri}\" od:numId=\"\{instance}\"><od:abstractNumId od:val=\"\{abstract_id}\"/></od:num>",
  )
  output.to_string()
}
