///|
fn WordTree::page_borders(
  self : WordTree,
  section : Int?,
  themes : Map[String, String],
) -> @layout.PageBorders raise @failure.Failure {
  guard section is Some(section) else { return @layout.PageBorders::new() }
  let roots = self.children[section].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == "pgBorders"
  })
  guard roots.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate page borders")
  }
  guard roots.get(0) is Some(id) else { return @layout.PageBorders::new() }
  let node = self.nodes[id]
  let source = self.source[node.start:node.end]
  guard node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["offsetFrom", "display", "zOrder"].contains(a.name)
    }) &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject("protected-content", "Unknown page border properties")
  }
  let sides : Array[@layout.PageBorder] = []
  let seen : Map[String, Bool] = Map([])
  for child in self.children[id] {
    let side = self.nodes[child]
    guard side.uri == word_uri &&
      ["top", "left", "bottom", "right"].contains(side.name) &&
      !seen.contains(side.name) &&
      self.children[child].is_empty() &&
      side.text.trim().is_empty() &&
      side.attributes.all(a => {
        a.uri == word_uri &&
        [
          "val", "color", "themeColor", "themeTint", "themeShade", "sz", "space",
          "shadow", "frame",
        ].contains(a.name)
      }) &&
      ["0", "false", "off"].contains(
        side.attribute("shadow", uri=word_uri).unwrap_or("0"),
      ) &&
      ["0", "false", "off"].contains(
        side.attribute("frame", uri=word_uri).unwrap_or("0"),
      ) else {
      @failure.reject("protected-content", "Unknown page border side")
    }
    seen[side.name] = true
    let kind = side.attribute("val", uri=word_uri).unwrap_or("none")
    guard ["single", "double", "dashed", "dotted", "none", "nil"].contains(kind) else {
      @failure.reject(
        "protected-content", "This page border style requires rendering support",
      )
    }
    if kind == "none" || kind == "nil" {
      continue
    }
    let color = theme_node_color(
      side,
      side.attribute("color", uri=word_uri).unwrap_or("auto"),
      themes,
    ).to_lower()
    sides.push({
      side: side.name,
      style: kind,
      themeColor: side
      .attribute("themeColor", uri=word_uri)
      .filter(name => name != "none")
      .map(word_theme_color_name),
      color: if color == "auto" {
        "000000"
      } else {
        color
      },
      width: self.number(id, side.name, "sz").unwrap_or(4) / 8,
      space: self.number(id, side.name, "space").unwrap_or(0),
    })
  }
  let result : @layout.PageBorders = {
    offsetFrom: node.attribute("offsetFrom", uri=word_uri).unwrap_or("text"),
    display: node.attribute("display", uri=word_uri).unwrap_or("allPages"),
    zOrder: node.attribute("zOrder", uri=word_uri).unwrap_or("front"),
    sides,
  }
  result.validate()
  result
}

///|
fn Session::page_borders_query(
  self : Session,
  tree : WordTree,
  index : Int,
) -> Json {
  try {
    let section = self.editable_page_section(tree, target=Some(index))
    let reason = self.theme_edit_reason()
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    { "value": tree.page_borders(section, self.theme_values()), "reason": "" }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": @layout.PageBorders::new(), "reason": message }
  }
}

///|
pub fn Session::set_page_borders(
  self : Session,
  revision : Int,
  sectionIndex : Int,
  borders : @layout.PageBorders?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if borders is Some(borders) {
    borders.validate() catch {
      _ => @failure.reject("invalid-operation", "Invalid page borders")
    }
  }
  let borders = borders.map(value => {
    ..value,
    sides: ["top", "left", "bottom", "right"].filter_map(name => {
      value.sides
      .iter()
      .find_first(side => side.side == name)
      .map(side => { ..side, color: side.color.to_lower(), })
    }),
  })
  let reason = self.theme_edit_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree, target=Some(sectionIndex))
  let themes = self.theme_values()
  let old = tree.page_borders(section, themes)
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  if borders is Some(value) &&
    value.sides.any(side => side.themeColor is Some(_)) &&
    self.theme_part() is None {
    ignore(self.new_word_part("theme", parts, part_edits, created))
  }
  let view = { ..self, parts, }
  let themes = view.theme_values()
  let borders = borders.map(value => {
    ..value,
    sides: value.sides.map(side => {
      guard side.themeColor is Some(slot) else { return side }
      let previous = old.sides
        .iter()
        .find_first(previous => {
          previous.side == side.side && previous.themeColor == side.themeColor
        })
      {
        ..side,
        color: previous
        .map(previous => previous.color)
        .unwrap_or_else(() => {
          themes
          .get(theme_color_name(slot))
          .unwrap_or_else(() => {
            @failure.reject(
              "protected-content",
              "Missing or unsupported theme color: " + slot,
            )
          })
        }),
      }
    }),
  })
  if section is None && borders is None {
    return self.edit_state()
  }
  let (candidate, edits, section) = page_section(original, tree, section)
  let tree = WordTree::new(candidate)
  let target = tree.child(section, "pgBorders")
  if borders is None && target is None {
    return self.edit_state()
  }
  if borders is Some(value) &&
    target is Some(_) &&
    value.to_json() == old.to_json() {
    return self.edit_state()
  }
  let markup = StringBuilder()
  if borders is Some(value) {
    markup <+
      "<w:pgBorders xmlns:w=\"\{word_uri}\" w:offsetFrom=\"\{value.offsetFrom}\" w:display=\"\{value.display}\" w:zOrder=\"\{value.zOrder}\">"
    for name in ["top", "left", "bottom", "right"] {
      if value.sides.iter().find_first(b => b.side == name) is Some(side) {
        markup <+ "<w:\{name} w:val=\"\{side.style}\""
        let original = target.bind(id => tree.child(id, name))
        if original is Some(id) &&
          old.sides.any(previous => {
            previous.side == name &&
            previous.color == side.color &&
            previous.themeColor == side.themeColor
          }) {
          // Retain theme bindings when only geometry or another side changes.
          for field in ["color", "themeColor", "themeTint", "themeShade"] {
            if tree.nodes[id].attribute(field, uri=word_uri) is Some(value) {
              markup <+ " w:\{field}=\"\{property_attribute(value)}\""
            }
          }
        } else {
          markup <+ " w:color=\"\{side.color}\""
          if side.themeColor is Some(slot) {
            markup <+ " w:themeColor=\"\{slot}\""
          }
        }
        markup <+
          " w:sz=\"\{(side.width * 8).to_int()}\" w:space=\"\{side.space.to_int()}\"/>"
      }
    }
    markup <+ "</w:pgBorders>"
  }
  let change : @xml.SourceChange? = if target is None &&
    !tree.nodes[section].empty {
    let before = [
      "headerReference", "footerReference", "footnotePr", "endnotePr", "type", "pgSz",
      "pgMar", "paperSrc",
    ]
    let previous = tree.children[section]
      .filter(id => {
        tree.nodes[id].uri == word_uri && before.contains(tree.nodes[id].name)
      })
      .last()
    Some({
      node: section,
      offset: previous
      .map(id => tree.nodes[id].end)
      .unwrap_or(tree.nodes[section].opening_end) -
      tree.nodes[section].start,
      length: 0,
      xml: markup.to_string(),
    })
  } else {
    properties_change(tree, candidate, section, "pgBorders", markup.to_string())
  }
  guard change is Some(change) else { return self.edit_state() }
  let (candidate, edit) = candidate.edit_source([change])
  edits.push(edit)
  ignore(WordTree::new(candidate).page_borders(Some(section), themes))
  let paragraphs = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let pending = self.typing_format
  view.validate_page_border_geometry(candidate)
  self.commit_edit(
    {
      xml: edits,
      parts: part_edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes: edits.fold(init=0, (n, e) => n + edit_bytes(e)) +
      xml_part_edit_bytes(part_edits, created),
    },
    candidate,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}

///|
fn Session::validate_page_border_geometry(
  self : Session,
  document : @xml.Document,
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  let themes = self.theme_values()
  let borders = tree
    .page_sections()
    .map(section => tree.page_borders(section, themes))
  if borders.all(border => border.sides.is_empty()) {
    return
  }
  let flow = self.flow_from(document)
  for index, borders in borders {
    if !borders.sides.is_empty() {
      let page = if index == 0 {
        flow.page
      } else {
        flow.sectionBreaks[index - 1].page
      }
      ignore(borders.fills(page, 0))
      ignore(borders.fills(page, 1))
    }
  }
}
