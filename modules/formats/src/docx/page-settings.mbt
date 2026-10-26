///|
fn WordTree::page_values(
  self : WordTree,
  section : Int,
  base : @layout.PageSetup,
) -> @layout.PageSetup raise @failure.Failure {
  {
    width: self
    .number(section, "pgSz", "w")
    .map(v => v / 20)
    .unwrap_or(base.width),
    height: self
    .number(section, "pgSz", "h")
    .map(v => v / 20)
    .unwrap_or(base.height),
    top: self
    .number(section, "pgMar", "top")
    .map(v => v / 20)
    .unwrap_or(base.top),
    right: self
    .number(section, "pgMar", "right")
    .map(v => v / 20)
    .unwrap_or(base.right),
    bottom: self
    .number(section, "pgMar", "bottom")
    .map(v => v / 20)
    .unwrap_or(base.bottom),
    left: self
    .number(section, "pgMar", "left")
    .map(v => v / 20)
    .unwrap_or(base.left),
  }
}

///|
fn default_page_setup() -> @layout.PageSetup {
  { width: 612, height: 792, top: 72, right: 72, bottom: 72, left: 72, }
}

///|
fn validate_page_setup(page : @layout.PageSetup) -> Unit raise @failure.Failure {
  guard page.width >= 36 &&
    page.width <= 14400 &&
    page.height >= 36 &&
    page.height <= 14400 &&
    page.left >= 0 &&
    page.right >= 0 &&
    page.top >= 0 &&
    page.bottom >= 0 &&
    page.width - page.left - page.right >= 12 &&
    page.height - page.top - page.bottom >= 12 &&
    [page.width, page.height, page.left, page.right, page.top, page.bottom].all(v => {
        v >= 0 && v <= 14400 && v * 20 == (v * 20).to_int().to_double()
      },
    ) else {
    @failure.reject(
      "invalid-operation", "Page dimensions and margins require integer twips and a usable content area",
    )
  }
}

///|
fn Session::editable_page_section(
  self : Session,
  tree : WordTree,
  target~ : Int? = None,
) -> Int? raise @failure.Failure {
  let body = tree.child(0, "body").unwrap()
  let sections = tree.page_sections()
  guard target is Some(_) ||
    (
      sections.length() == 1 &&
      sections[0].map(id => tree.nodes[id].parent == body).unwrap_or(true)
    ) else {
    @failure.reject(
      "protected-content", "Page setup for multiple sections is not supported yet",
    )
  }
  let selected = match target {
    None => sections[0]
    Some(index) => {
      guard sections.get(index) is Some(section) else {
        @failure.reject("invalid-operation", "Unknown page section")
      }
      section
    }
  }
  if self.settings_part() is Some(part) {
    let settings = WordTree::new(self.part_xml(part))
    for name in ["documentProtection", "mirrorMargins", "gutterAtTop"] {
      let targets = settings.children[0].filter(id => {
        settings.nodes[id].uri == word_uri && settings.nodes[id].name == name
      })
      guard targets.length() <= 1 else {
        @failure.reject("protected-content", "Duplicate page layout setting")
      }
      if targets.get(0) is Some(id) {
        let value = settings.nodes[id]
          .attribute(
            if name == "documentProtection" {
              "enforcement"
            } else {
              "val"
            },
            uri=word_uri,
          )
          .unwrap_or(if name == "documentProtection" { "0" } else { "1" })
        guard ["0", "false", "off"].contains(value) else {
          @failure.reject(
            "protected-content", "Unsupported protected or mirrored page setup",
          )
        }
      }
    }
  }
  if selected is Some(id) {
    let node = tree.nodes[id]
    guard node.parent != body || tree.children[body].last() == Some(id) else {
      @failure.reject(
        "protected-content", "Section properties must end the document body",
      )
    }
    guard node.attributes
      .iter()
      .all(a => {
        a.uri == word_uri && ["rsidR", "rsidRPr", "rsidSect"].contains(a.name)
      }) &&
      node.text.trim().is_empty() else {
      @failure.reject("protected-content", "Unknown section attributes or text")
    }
    let diagnostics : Array[String] = []
    tree.diagnose_properties(id, self.main, diagnostics)
    guard diagnostics.is_empty() else {
      @failure.reject("protected-content", diagnostics[0])
    }
    for
      (name, allowed) in [
        ("pgSz", ["w", "h", "orient", "code"]),
        (
          "pgMar",
          ["top", "right", "bottom", "left", "header", "footer", "gutter"],
        ),
      ] {
      let targets = tree.children[id].filter(id => {
        tree.nodes[id].uri == word_uri && tree.nodes[id].name == name
      })
      guard targets.length() <= 1 else {
        @failure.reject("protected-content", "Duplicate page property")
      }
      if targets.get(0) is Some(target) {
        let property = tree.nodes[target]
        guard tree.children[target].is_empty() &&
          property.text.trim().is_empty() &&
          property.attributes
          .iter()
          .all(a => a.uri == word_uri && allowed.contains(a.name)) else {
          @failure.reject("protected-content", "Unknown page property markup")
        }
        if name == "pgSz" {
          guard ["portrait", "landscape"].contains(
            property.attribute("orient", uri=word_uri).unwrap_or("portrait"),
          ) else {
            @failure.reject("protected-content", "Unknown page orientation")
          }
        } else {
          guard tree.number(id, "pgMar", "gutter").unwrap_or(0) == 0 else {
            @failure.reject(
              "protected-content", "Gutter layout is not supported yet",
            )
          }
        }
      }
    }
  }
  selected
}

///|
pub fn Session::page_setup(
  self : Session,
  revision : Int,
  section~ : Int = 0,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  guard section >= 0 && section < 1024 else {
    @failure.reject("invalid-operation", "Invalid page section")
  }
  let mut section_count = 0
  try {
    section_count = tree.page_sections().length()
    let index = section
    let section = self.editable_page_section(tree, target=Some(index))
    let page = match section {
      Some(id) => tree.page_values(id, default_page_setup())
      None => default_page_setup()
    }
    validate_page_setup(page)
    {
      "revision": revision,
      "sectionCount": section_count,
      "page": {
        "section": index,
        "startType": tree.section_start_type(section),
        "footnotesAt": self.section_footnotes_at(tree, section),
        "width": page.width,
        "height": page.height,
        "top": page.top,
        "right": page.right,
        "bottom": page.bottom,
        "left": page.left,
      },
      "reason": "",
      "background": self.page_background_query(tree),
      "borders": self.page_borders_query(tree, index),
      "numbering": self.page_numbering_query(tree, index),
      "columns": self.page_columns_query(tree, index),
    }
  } catch {
    @failure.Failure(code="invalid-operation", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      {
        "revision": revision,
        "sectionCount": section_count,
        "page": Json::null(),
        "reason": message,
        "background": self.page_background_query(tree),
        "borders": self.page_borders_query(tree, section),
        "numbering": self.page_numbering_query(tree, section),
        "columns": self.page_columns_query(tree, section),
      }
  }
}

///|
/// Changes one section's page geometry and optional start type in one source transaction.
pub fn Session::set_page_setup(
  self : Session,
  revision : Int,
  sectionIndex : Int,
  page : @layout.PageSetup,
  orientation~ : String? = None,
  startType~ : String? = None,
  footnotesAt~ : String? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if footnotesAt is Some(position) {
    guard ["pageBottom", "beneathText"].contains(position) else {
      @failure.reject("invalid-operation", "Invalid footnote placement")
    }
  }
  if startType is Some(kind) {
    guard ["nextPage", "oddPage", "evenPage", "continuous"].contains(kind) else {
      @failure.reject("invalid-operation", "Unsupported section start type")
    }
  }
  let page = match orientation {
    None => page
    Some(value) => {
      guard ["portrait", "landscape"].contains(value) else {
        @failure.reject("invalid-operation", "Invalid page orientation")
      }
      if (page.width > page.height) == (value == "landscape") ||
        page.width == page.height {
        page
      } else if value == "landscape" {
        {
          width: page.height,
          height: page.width,
          left: page.bottom,
          top: page.left,
          right: page.top,
          bottom: page.right,
        }
      } else {
        {
          width: page.height,
          height: page.width,
          left: page.top,
          top: page.right,
          right: page.bottom,
          bottom: page.left,
        }
      }
    }
  }
  validate_page_setup(page)
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree, target=Some(sectionIndex))
  let current = match section {
    Some(id) => tree.page_values(id, default_page_setup())
    None => default_page_setup()
  }
  ignore(tree.page_columns(section).width(page))
  let page_changed = !(current.width == page.width &&
    current.height == page.height &&
    current.top == page.top &&
    current.right == page.right &&
    current.bottom == page.bottom &&
    current.left == page.left)
  let start_changed = startType
    .map(kind => kind != tree.section_start_type(section))
    .unwrap_or(false)
  let notes_changed = match footnotesAt {
    Some(position) => position != self.section_footnotes_at(tree, section)
    None => false
  }
  if !page_changed && !start_changed && !notes_changed {
    return self.edit_state()
  }
  let (initial, edits, section) = page_section(original, tree, section)
  let mut candidate = initial
  for
    (name, values) in [
      (
        "pgSz",
        Map::from_array([
          ("w", Some((page.width * 20).to_int().to_string())),
          ("h", Some((page.height * 20).to_int().to_string())),
          (
            "orient",
            Some(
              if page.width > page.height {
                "landscape"
              } else {
                "portrait"
              },
            ),
          ),
          ("code", None),
        ]),
      ),
      (
        "pgMar",
        Map::from_array([
          ("top", Some((page.top * 20).to_int().to_string())),
          ("right", Some((page.right * 20).to_int().to_string())),
          ("bottom", Some((page.bottom * 20).to_int().to_string())),
          ("left", Some((page.left * 20).to_int().to_string())),
        ]),
      ),
    ] {
    if !page_changed {
      continue
    }
    let tree = WordTree::new(candidate)
    let markup = property_markup(
      tree,
      candidate,
      tree.child(section, name),
      name,
      Some(values),
    )
    let change : @xml.SourceChange? = if tree.child(section, name) is None &&
      !tree.nodes[section].empty {
      let node = tree.nodes[section]
      let earlier = [
        "headerReference", "footerReference", "footnotePr", "endnotePr", "type",
        "pgSz",
      ]
      let previous = tree.children[section]
        .filter(id => earlier.contains(tree.nodes[id].name))
        .last()
      Some({
        node: section,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(node.opening_end) -
        node.start,
        length: 0,
        xml: markup,
      })
    } else {
      properties_change(tree, candidate, section, name, markup)
    }
    if change is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
  }
  if start_changed && startType is Some(kind) {
    let tree = WordTree::new(candidate)
    if tree.section_start_change(candidate, section, kind) is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
  }
  if notes_changed && footnotesAt is Some(position) {
    let tree = WordTree::new(candidate)
    if tree.footnotes_at_change(candidate, section, position) is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
  }
  if edits.is_empty() {
    return self.edit_state()
  }
  let updated = WordTree::new(candidate)
  validate_page_setup(updated.page_values(section, default_page_setup()))
  self.validate_page_border_geometry(candidate)
  let paragraphs = updated.order.filter(id => {
    updated.nodes[id].uri == word_uri && updated.nodes[id].name == "p"
  })
  let mut bytes = 0
  for edit in edits {
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Page setup exceeds history budget")
    }
    bytes += count
  }
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: edits,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes,
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
