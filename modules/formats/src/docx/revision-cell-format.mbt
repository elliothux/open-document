///|
fn WordTree::check_cell_format_properties(
  self : WordTree,
  properties : Int,
  change~ : Int? = None,
) -> Unit raise @failure.Failure {
  let node = self.nodes[properties]
  let source = self.source[node.start:node.end]
  guard node.uri == word_uri &&
    node.name == "tcPr" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque cell properties require review support",
    )
  }
  let names : Set[String] = Set([])
  for id in self.children[properties] {
    let child = self.nodes[id]
    guard child.uri == word_uri && !names.contains(child.name) else {
      @failure.reject(
        "protected-content", "Foreign or duplicate cell properties",
      )
    }
    names.add(child.name)
    if change == Some(id) {
      continue
    }
    match child.name {
      "tcW" => ignore(self.preferred_table_width(id))
      "shd" => ignore(self.table_shading(properties, None))
      "tcBorders" => ignore(self.read_borders(properties, "tcBorders", None))
      "tcMar" =>
        ignore(
          self.table_margins(id, { top: 0, right: 0, bottom: 0, left: 0, }),
        )
      "vAlign" => ignore(self.cell_vertical_alignment(properties))
      "gridSpan" | "vMerge" => {
        guard self.children[id].is_empty() &&
          child.text.trim().is_empty() &&
          child.attributes.all(a => a.uri == word_uri && a.name == "val") else {
          @failure.reject("protected-content", "Unknown cell grid properties")
        }
        if child.name == "gridSpan" {
          let span = @string.parse_int(
            child.attribute("val", uri=word_uri).unwrap_or("1"),
          ) catch {
            _ => 0
          }
          guard span >= 1 && span <= 63 else {
            @failure.reject("protected-content", "Invalid cell grid span")
          }
        } else {
          guard ["restart", "continue"].contains(
            child.attribute("val", uri=word_uri).unwrap_or("continue"),
          ) else {
            @failure.reject("protected-content", "Invalid vertical merge state")
          }
        }
      }
      _ =>
        @failure.reject(
          "protected-content", "Unknown cell formatting requires review support",
        )
    }
  }
}

///|
fn WordTree::check_cell_property_revision(
  self : WordTree,
  id : Int,
) -> Int raise @failure.Failure {
  let change = self.nodes[id]
  guard change.uri == word_uri &&
    change.name == "tcPrChange" &&
    change.text.trim().is_empty() &&
    change.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    self.nodes.get(change.parent) is Some(properties) &&
    properties.uri == word_uri &&
    properties.name == "tcPr" &&
    self.nodes.get(properties.parent) is Some(cell) &&
    cell.uri == word_uri &&
    cell.name == "tc" &&
    self.table_children(cell.id, "tcPr").length() == 1 &&
    self.children[id] is [previous] &&
    self.child(cell.id, "p") is Some(paragraph) &&
    cell.attributes.all(a => {
      a.uri == word_uri &&
      ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
    }) &&
    self.children[cell.id].all(id => {
      self.nodes[id].uri == word_uri &&
      ["tcPr", "p"].contains(self.nodes[id].name)
    }) else {
    @failure.reject(
      "protected-content", "Cell formatting revision requires one ordinary previous property set",
    )
  }
  self.check_revision_paragraph(paragraph)
  ignore(comment_key(change.attribute("id", uri=word_uri).unwrap_or("")))
  self.check_cell_format_properties(properties.id, change=Some(id))
  self.check_cell_format_properties(previous)
  for name in ["tcW", "gridSpan", "vMerge"] {
    let signature = fn(props) {
      self
      .child(props, name)
      .map(id => {
        let node = self.nodes[id]
        (
          node.attribute("type", uri=word_uri),
          node.attribute("w", uri=word_uri),
          node.attribute("val", uri=word_uri),
        )
      })
    }
    guard signature(properties.id) == signature(previous) else {
      @failure.reject(
        "protected-content", "Cell grid revisions require structural review support",
      )
    }
  }
  for p in self.table_children(cell.id, "p") {
    if self.has_review_markup(p) {
      ignore(self.review_text_parts(p))
    } else {
      self.check_editable_paragraph(p, part="", notes=true)
      self.check_structure_paragraph(p)
    }
  }
  paragraph
}
