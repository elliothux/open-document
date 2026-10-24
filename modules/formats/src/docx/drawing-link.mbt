///|
fn WordTree::drawing_link_node(
  self : WordTree,
  drawing : Int,
  portable~ : Bool = false,
) -> (Int, Int?) raise @failure.Failure {
  let frame = self.drawing_data(drawing).0
  let identity = self.anchor_child(frame.id, "docPr")
  self.shape_children(identity, ["hlinkClick"]) catch {
    @failure.Failure(code="unsupported-layout", message~, ..) =>
      @failure.reject("protected-content", message)
    error => raise error
  }
  let link = self.drawing_child(identity, "hlinkClick")
  if link is Some(id) {
    let node = self.nodes[id]
    let rel = if portable {
      table_fragment_uri
    } else {
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    }
    let reference = if portable { "target" } else { "id" }
    guard self.children[id].is_empty() &&
      node.text.trim().is_empty() &&
      !self.source[node.start:node.end].contains("<!--") &&
      !self.source[node.start:node.end].contains("<?") &&
      node.attribute(reference, uri=rel) is Some(_) &&
      node.attributes.all(a => {
        (a.uri == rel && a.name == reference) ||
        (
          a.uri.is_empty() &&
          (match a.name {
            "tooltip" | "tgtFrame" => a.value.length() <= 2048
            "history" | "highlightClick" | "endSnd" =>
              ["0", "1", "true", "false"].contains(a.value)
            "action" | "invalidUrl" => a.value.is_empty()
            _ => false
          })
        )
      }) else {
      @failure.reject(
        "protected-content", "Extended drawing hyperlink requires support",
      )
    }
  }
  // Other nonvisual owners may carry separate actions; never overwrite them.
  guard !self
    .descendants(drawing)
    .any(id => {
      let node = self.nodes[id]
      node.uri == picture_drawing_uri &&
      ["hlinkClick", "hlinkHover"].contains(node.name) &&
      link != Some(id)
    }) else {
    @failure.reject(
      "protected-content", "Other drawing hyperlink actions require support",
    )
  }
  (identity, link)
}

///|
fn Session::drawing_link_target(
  self : Session,
  tree : WordTree,
  id : Int,
  links? : Map[String, @opc.Relationship],
  bookmarks? : Map[String, Bool],
) -> String? raise @failure.Failure {
  let (_, link) = tree.drawing_link_node(id)
  guard link is Some(link) else { return None }
  let key = tree.nodes[link]
    .attribute(
      "id",
      uri="http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    )
    .unwrap()
  let links = links.unwrap_or_else(() => self.hyperlink_relationships())
  guard links.get(key) is Some(relation) &&
    relation.external &&
    relation.kind ==
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" else {
    @failure.reject(
      "protected-content", "Unresolved drawing hyperlink relationship",
    )
  }
  check_hyperlink_target(relation.target)
  if relation.target.has_prefix("#") {
    let bookmarks = bookmarks.unwrap_or_else(() => tree.bookmark_targets())
    guard bookmarks.contains(relation.target[1:].to_owned().to_lower()) else {
      @failure.reject(
        "protected-content", "Unresolved or protected drawing bookmark hyperlink",
      )
    }
  }
  Some(relation.target)
}

///|
fn Session::editable_drawing_link(
  self : Session,
  tree : WordTree,
  id : Int,
) -> Int raise @failure.Failure {
  let paragraph = self.drawing_paragraph(tree, id)
  if tree.drawing_data(id).1.attribute("uri") == Some(word_shape_uri) {
    ignore(self.editable_shape(tree, id))
  } else {
    ignore(self.editable_picture(tree, id, replace=true))
  }
  guard !tree.shape_locked(id, "noSelect") else {
    @failure.reject("protected-content", "Drawing selection is locked")
  }
  paragraph
}

///|
fn Session::drawing_link_summary(
  self : Session,
  tree : WordTree,
  id : Int,
  links? : Map[String, @opc.Relationship],
  bookmarks? : Map[String, Bool],
) -> Json {
  try {
    ignore(self.editable_drawing_link(tree, id))
    {
      "target": self
      .drawing_link_target(tree, id, links?, bookmarks?)
      .map(value => Json(value))
      .unwrap_or(Json::null()),
      "reason": "",
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "target": Json::null(), "reason": message }
  }
}

///|
/// Edits an ordinary picture or shape's URL or #bookmark click target without changing its geometry.
pub fn Session::set_drawing_hyperlink(
  self : Session,
  revision : Int,
  id : Int,
  target : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if target is Some(target) {
    check_hyperlink_target(target)
  }
  let document = self.document()
  let tree = WordTree::new(document)
  if target is Some(target) && target.has_prefix("#") {
    guard tree.bookmark_targets().contains(target[1:].to_owned().to_lower()) else {
      @failure.reject(
        "invalid-operation", "Internal hyperlink requires an existing editable bookmark",
      )
    }
  }
  let paragraph = self.editable_drawing_link(tree, id)
  let current = self.drawing_link_target(tree, id)
  if current == target {
    return self.edit_result([])
  }
  let (identity, existing) = tree.drawing_link_node(id)
  let node = tree.nodes[identity]
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let relation = target.map(target => {
    self.ensure_hyperlink_relationships(
      self.main,
      [target],
      self.hyperlink_relationships(),
      parts,
      edits,
      created,
    )[target]
  })
  let change : @xml.SourceChange = if existing is Some(link) {
    let previous = tree.nodes[link]
    if relation is Some(relation) {
      let attr = previous.attributes
        .iter()
        .find_first(a => {
          a.name == "id" &&
          a.uri ==
          "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        })
        .unwrap()
      {
        node: link,
        offset: attr.start - previous.start,
        length: attr.end - attr.start,
        xml: relation,
      }
    } else {
      {
        node: identity,
        offset: previous.start - node.start,
        length: previous.end - previous.start,
        xml: "",
      }
    }
  } else {
    let markup = "<od:hlinkClick xmlns:od=\"\{picture_drawing_uri}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"\{relation.unwrap()}\"/>"
    if node.empty {
      {
        node: identity,
        offset: node.opening_end - node.start - 2,
        length: 2,
        xml: ">" + markup + "</\{node.qualified}>",
      }
    } else {
      {
        node: identity,
        offset: node.closing_start - node.start,
        length: 0,
        xml: markup,
      }
    }
  }
  let (candidate, xml) = document.edit_source([change])
  let bytes = edit_bytes(xml) + xml_part_edit_bytes(edits, created)
  guard bytes <= history_byte_limit else {
    @failure.reject(
      "limit-exceeded", "Drawing hyperlink history exceeds budget",
    )
  }
  self.commit_edit(
    {
      xml: [xml],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes,
    },
    candidate,
    parts~,
  )
  self.edit_result([paragraph])
}
