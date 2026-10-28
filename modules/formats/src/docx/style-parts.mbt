///|
let style_reference_names : ReadOnlyArray[String] = [
  "pStyle", "rStyle", "tblStyle", "basedOn", "next", "link", "numStyleLink", "styleLink",
]

///|
fn Session::style_part_names(self : Session) -> Array[String] {
  let names : Array[String] = []
  for key, kind in self.opc.types {
    if kind.has_prefix(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.",
      ) &&
      kind.has_suffix("+xml") {
      names.push(self.opc.names[key])
    }
  }
  for name, document in self.parts {
    if document.nodes()[0].uri == word_uri && !names.contains(name) {
      names.push(name)
    }
  }
  names
}

///|
fn Styles::can_delete(self : Styles, key : String) -> Bool {
  guard self.tree is Some(tree) && self.ids.get(key) is Some(id) else {
    return false
  }
  let node = tree.nodes[id]
  ["1", "true", "on"].contains(
    node.attribute("customStyle", uri=word_uri).unwrap_or("0"),
  ) &&
  !["1", "true", "on"].contains(
    node.attribute("default", uri=word_uri).unwrap_or("0"),
  )
}

///|
fn Styles::is_linked(self : Styles, key : String) -> Bool {
  guard self.tree is Some(tree) && self.ids.get(key) is Some(id) else {
    return false
  }
  tree.child(id, "link") is Some(_) ||
  self.ids.values().any(other => tree.value(other, "link") == Some(key))
}

///|
fn Session::validate_style_transition(
  self : Session,
  before : Styles,
  after : Styles,
  document : @xml.Document,
  parts~ : Map[String, @xml.Document] = self.parts,
) -> Array[Int32] raise @failure.Failure {
  guard after.ids.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Too many styles for a shared style edit")
  }
  let tree = after.tree.unwrap()
  for key, id in after.ids {
    let kind = tree.nodes[id]
      .attribute("type", uri=word_uri)
      .unwrap_or("paragraph")
    if !["paragraph", "character"].contains(kind) {
      continue
    }
    let supported = try {
      before.validate_style(key, kind)
      true
    } catch {
      _ => false
    }
    if supported {
      after.validate_style(key, kind)
    }
  }
  let old = WordTree::new(self.document())
  let current = WordTree::new(document)
  let after_session = { ..self, document: Some(document), parts, }
  let mut before_numbers : NumberingContext? = None
  let mut after_numbers : NumberingContext? = None
  let paragraphs = old.order.filter(id => {
    old.nodes[id].uri == word_uri && old.nodes[id].name == "p"
  })
  for paragraph in paragraphs {
    let supported = try {
      let base = before.paragraph_style(old, paragraph, [])
      let mut value = match old.child(paragraph, "pPr") {
        None => base
        Some(id) => paragraph_properties(old, id, base)
      }
      if before.numbering_reference(old, paragraph) is Some((id, level)) {
        let numbers = match before_numbers {
          Some(numbers) => numbers
          None => {
            let numbers = self.numbering_context()
            before_numbers = Some(numbers)
            numbers
          }
        }
        value = numbers.properties(old, value, id, level)
      }
      validate_paragraph_style_values(value)
      true
    } catch {
      _ => false
    }
    if supported {
      let base = after.paragraph_style(current, paragraph, [])
      let mut value = match current.child(paragraph, "pPr") {
        None => base
        Some(id) => paragraph_properties(current, id, base)
      }
      if after.numbering_reference(current, paragraph) is Some((id, level)) {
        let numbers = match after_numbers {
          Some(numbers) => numbers
          None => {
            let numbers = after_session.numbering_context()
            after_numbers = Some(numbers)
            numbers
          }
        }
        value = numbers.properties(current, value, id, level)
      }
      validate_paragraph_style_values(value)
    }
  }
  if after_numbers is Some(numbers) {
    let abstracts : Map[Int32, Bool] = Map([])
    for definition in numbers.definitions.values() {
      abstracts[definition.abstract_id] = true
    }
    ignore(numbers.validate_level_labels(current, after, abstracts))
  }
  paragraphs
}
