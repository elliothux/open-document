///|
fn picture_identity(value : String) -> String {
  @string.parse_int64(value.trim()[:], base=10).to_string() catch {
    _ => value
  }
}

///|
fn WordTree::check_picture_references(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let tree = self
  let target = tree.nodes[id]
  let identities : Map[String, Bool] = Map([])
  for child in tree.descendants(id) {
    let node = tree.nodes[child]
    if (node.uri == picture_inline_uri && node.name == "docPr") ||
      node.name == "cNvPr" {
      if node.attribute("id") is Some(value) {
        identities[picture_identity(value)] = true
      }
    }
  }
  for node in tree.nodes.values() {
    if node.start >= target.start && node.end <= target.end {
      continue
    }
    for attribute in node.attributes {
      if (
          ["spid", "spId", "shapeId", "shapeIdRef"].contains(attribute.name) ||
          (["stCxn", "endCxn"].contains(node.name) && attribute.name == "id")
        ) &&
        identities.contains(picture_identity(attribute.value)) {
        @failure.reject(
          "protected-content", "Referenced pictures require reference-aware deletion",
        )
      }
    }
  }
}

///|
pub fn Session::delete_picture(
  self : Session,
  revision : Int,
  id : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let (_, paragraph, _, _) = self.editable_picture(tree, id, remove=true)
  self.delete_drawing(document, tree, id, paragraph)
}

///|
fn Session::delete_drawing(
  self : Session,
  document : @xml.Document,
  tree : WordTree,
  id : Int,
  paragraph : Int,
) -> Json raise @failure.Failure {
  let target = tree.nodes[id]
  let offset = self.texts
    .iter()
    .filter(item => {
      item.paragraph == paragraph && tree.nodes[item.id].start < target.start
    })
    .fold(init=0, (sum, item) => sum + inline_text(tree.nodes[item.id]).length())
  let (candidate, xml) = document.edit_source([
    {
      node: target.parent,
      offset: target.start - tree.nodes[target.parent].start,
      length: target.end - target.start,
      xml: "",
    },
  ])
  let text = docx_texts(WordTree::new(candidate))
    .filter(item => item.paragraph == paragraph)
    .map(item => inline_text(candidate.node(item.id)))
    .join("")
  let boundary = editing_boundaries(text, true)
    .iter()
    .find_first(value => value >= offset)
    .unwrap_or(text.length())
  let position : Position = {
    paragraph,
    offset: boundary,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let after = try {
    self.check_position_in(candidate, position)
    Some({ anchor: position, focus: position, })
  } catch {
    @failure.Failure(..) => self.selection
  }
  // Package cleanup needs ownership of shared media and unknown relationships.
  self.commit_edit(
    {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    candidate,
  )
  self.edit_result([paragraph])
}
