///|
priv struct NumberingContext {
  tree : WordTree
  document : @xml.Document
  part : String
  instances : Map[Int, Int]
  abstracts : Map[Int, Int]
  definitions : Map[Int, NumberDefinition]
}

///|
fn Session::numbering_context(
  self : Session,
) -> NumberingContext raise @failure.Failure {
  let relationships = self
    .relationships()
    .filter(rel => {
      rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
    })
  guard relationships.length() == 1 && !relationships[0].external else {
    @failure.reject(
      "invalid-numbering", "Missing or invalid numbering relationship",
    )
  }
  let document = self.part_xml(relationships[0].target)
  let numbers = WordTree::new(document)
  guard numbers.nodes[0].uri == word_uri &&
    numbers.nodes[0].name == "numbering" &&
    numbers.children[0].length() <= 8192 else {
    @failure.reject("invalid-numbering", "Invalid or oversized numbering part")
  }
  let instances : Map[Int, Int] = Map([])
  let abstracts : Map[Int, Int] = Map([])
  for id in numbers.children[0] {
    let node = numbers.nodes[id]
    if node.uri != word_uri || !["num", "abstractNum"].contains(node.name) {
      continue
    }
    let field = if node.name == "num" { "numId" } else { "abstractNumId" }
    let index = numbering_integer(
      node.attribute(field, uri=word_uri).unwrap_or("-1"),
      2147483646,
    )
    let values = if node.name == "num" { instances } else { abstracts }
    guard !values.contains(index) && values.length() < 4096 else {
      @failure.reject(
        "invalid-numbering", "Duplicate or excessive numbering definitions",
      )
    }
    values[index] = id
  }
  {
    tree: numbers,
    document,
    part: relationships[0].target,
    instances,
    abstracts,
    definitions: Map([]),
  }
}

///|
fn NumberingContext::definition(
  self : NumberingContext,
  id : Int,
) -> NumberDefinition raise @failure.Failure {
  match self.definitions.get(id) {
    Some(value) => value
    None => {
      let value = self.tree.number_definition(
        id,
        self.instances,
        self.abstracts,
      )
      self.definitions[id] = value
      value
    }
  }
}

///|
fn NumberingContext::properties(
  self : NumberingContext,
  tree : WordTree,
  paragraph : @layout.Paragraph,
  instance : Int,
  index : Int,
) -> @layout.Paragraph raise @failure.Failure {
  let mut paragraph = self.level_properties(paragraph, instance, index)
  if tree.child(paragraph.id, "pPr") is Some(p) {
    paragraph = paragraph_properties(tree, p, paragraph)
  }
  paragraph
}

///|
fn NumberingContext::level_properties(
  self : NumberingContext,
  paragraph : @layout.Paragraph,
  instance : Int,
  index : Int,
) -> @layout.Paragraph raise @failure.Failure {
  let level = self.level(instance, index)
  match self.tree.child(level.node, "pPr") {
    None => paragraph
    Some(p) => paragraph_properties(self.tree, p, paragraph)
  }
}

///|
fn Session::formatting_paragraphs(
  self : Session,
  document : @xml.Document,
  paragraphs : Array[Int],
) -> Array[@layout.Paragraph] raise @failure.Failure {
  let tree = WordTree::new(document)
  let styles = self.styles([])
  let mut context : NumberingContext? = None
  paragraphs.map(id => {
    let paragraph = self.paragraph(tree, styles, id, [])
    match styles.numbering_reference(tree, id) {
      None => paragraph
      Some((instance, level)) => {
        let numbers = match context {
          Some(value) => value
          None => {
            let value = self.numbering_context()
            context = Some(value)
            value
          }
        }
        numbers.properties(tree, paragraph, instance, level)
      }
    }
  })
}
