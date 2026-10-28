///|
/// Deletes a custom style and remaps its WordprocessingML references to an explicit replacement.
pub fn Session::delete_style(
  self : Session,
  revision : Int32,
  key : String,
  replacement : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let styles = self.styles([])
  guard styles.tree is Some(tree) &&
    styles.ids.get(key) is Some(id) &&
    key != replacement else {
    @failure.reject("invalid-style", "Invalid style deletion target")
  }
  let kind = tree.nodes[id]
    .attribute("type", uri=word_uri)
    .unwrap_or("paragraph")
  guard ["paragraph", "character"].contains(kind) else {
    @failure.reject("invalid-style", "Unsupported style type")
  }
  styles.validate_style(key, kind)
  styles.validate_style(replacement, kind)
  guard styles.can_delete(key) else {
    @failure.reject(
      "protected-content", "Only non-default custom styles can be deleted",
    )
  }
  guard !styles.chain(replacement, []).contains(id) else {
    @failure.reject(
      "invalid-style", "The replacement cannot depend on the deleted style",
    )
  }
  guard styles.ids.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Too many styles for a shared style edit")
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let mut main = self.document()
  let mut main_edits : Array[@xml.Edit] = []
  let mut bytes = 0
  let mut references = 0
  let value = property_attribute(replacement).split("'").join("&apos;")
  for part in self.style_part_names() {
    let document = self.part_xml(part)
    let tree = WordTree::new(document)
    let removed = if tree.nodes[0].uri == word_uri &&
      tree.nodes[0].name == "styles" {
      tree.children[0].filter(id => {
        tree.nodes[id].uri == word_uri &&
        tree.nodes[id].name == "style" &&
        tree.nodes[id].attribute("styleId", uri=word_uri) == Some(key)
      })
    } else {
      []
    }
    let changes : Array[@xml.SourceChange] = []
    for id in removed {
      let node = tree.nodes[id]
      changes.push({
        node: 0,
        offset: node.start - tree.nodes[0].start,
        length: node.end - node.start,
        xml: "",
      })
    }
    for id in tree.order {
      let node = tree.nodes[id]
      let inside = for parent = id
                       parent >= 0
                       parent = tree.nodes[parent].parent {
        if removed.contains(parent) {
          break true
        }
      } nobreak {
        false
      }
      if inside ||
        node.uri != word_uri ||
        !style_reference_names.contains(node.name) {
        continue
      }
      if node.name == "link" && node.attribute("val", uri=word_uri) == Some(key) {
        guard tree.nodes[node.parent].uri == word_uri &&
          tree.nodes[node.parent].name == "style" &&
          node.attributes.iter().all(a => a.uri == word_uri && a.name == "val") &&
          tree.children[id].is_empty() &&
          node.text.trim().is_empty() &&
          tree.children[node.parent]
          .filter(child => {
            tree.nodes[child].uri == word_uri &&
            tree.nodes[child].name == "link"
          })
          .length() ==
          1 else {
          @failure.reject(
            "protected-content", "Unknown style link markup prevents deletion",
          )
        }
        let markup = property_markup(tree, document, Some(id), "link", None)
        if properties_change(tree, document, node.parent, "link", markup)
          is Some(change) {
          changes.push(change)
        }
        references += 1
        guard references <= 65536 else {
          @failure.reject("limit-exceeded", "Too many style references")
        }
        continue
      }
      for attribute in node.attributes {
        if attribute.uri == word_uri &&
          attribute.name == "val" &&
          attribute.value == key {
          references += 1
          guard references <= 65536 else {
            @failure.reject("limit-exceeded", "Too many style references")
          }
          changes.push({
            node: id,
            offset: attribute.start - node.start,
            length: attribute.end - attribute.start,
            xml: value,
          })
        }
      }
    }
    if changes.is_empty() {
      continue
    }
    let (candidate, edit) = document.edit_source(changes)
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Style deletion exceeds history budget")
    }
    bytes += count
    if part == self.main {
      main = candidate
      main_edits = [edit]
    } else {
      parts[part] = candidate
      edits[part] = [edit]
    }
  }
  let view = { ..self, parts, document: Some(main), }
  let updated = view.styles([])
  let affected = self.validate_style_transition(styles, updated, main, parts~)
  let pending = self.typing_format.map(patch => {
    if patch.style == Set(key) {
      { ..patch, style: Set(replacement), }
    } else {
      patch
    }
  })
  self.commit_edit(
    {
      xml: main_edits,
      parts: edits,
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(selection => selection.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    main,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
