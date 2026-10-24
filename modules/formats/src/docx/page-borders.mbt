///|
fn WordTree::page_borders(
  self : WordTree,
  section~ : Int? = None,
) -> @layout.PageBorders raise @failure.Failure {
  let sections = if section is Some(id) {
    [id]
  } else {
    self.order.filter(id => {
      self.nodes[id].uri == word_uri && self.nodes[id].name == "sectPr"
    })
  }
  guard sections.length() <= 1 else {
    @failure.reject(
      "protected-content", "Page borders for multiple sections are unsupported",
    )
  }
  guard sections.get(0) is Some(section) else {
    return @layout.PageBorders::new()
  }
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
        ["val", "color", "sz", "space", "shadow", "frame"].contains(a.name)
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
    guard ["single", "none", "nil"].contains(kind) else {
      @failure.reject(
        "protected-content", "This page border style requires rendering support",
      )
    }
    if kind != "single" {
      continue
    }
    let color = side
      .attribute("color", uri=word_uri)
      .unwrap_or("auto")
      .to_lower()
    sides.push({
      side: side.name,
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
fn Session::page_borders_query(self : Session, tree : WordTree) -> Json {
  try {
    ignore(self.editable_page_section(tree))
    let reason = self.theme_edit_reason()
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    { "value": tree.page_borders(), "reason": "" }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": @layout.PageBorders::new(), "reason": message }
  }
}

///|
pub fn Session::set_page_borders(
  self : Session,
  revision : Int,
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
  let old = tree.page_borders()
  let section = self.editable_page_section(tree)
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
        markup <+
          "<w:\{name} w:val=\"single\" w:color=\"\{side.color.to_lower()}\" w:sz=\"\{(side.width * 8).to_int()}\" w:space=\"\{side.space.to_int()}\"/>"
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
  ignore(WordTree::new(candidate).page_borders())
  let paragraphs = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let pending = self.typing_format
  self.validate_page_border_geometry(candidate)
  self.commit_edit(
    {
      xml: edits,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes: edits.fold(init=0, (n, e) => n + edit_bytes(e)),
    },
    candidate,
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
  let borders = tree
    .page_sections()
    .map(section => {
      section
      .map(id => tree.page_borders(section=Some(id)))
      .unwrap_or(@layout.PageBorders::new())
    })
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
