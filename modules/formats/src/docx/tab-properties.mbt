///|
fn WordTree::valid_tabs(self : WordTree, id : Int) -> Bool {
  let node = self.nodes[id]
  if !node.empty &&
    (
      self.source[node.opening_end:node.closing_start].contains("<!--") ||
      self.source[node.opening_end:node.closing_start].contains("<?")
    ) {
    return false
  }
  if !node.attributes.is_empty() ||
    !node.text.trim().is_empty() ||
    self.children[id].length() > 128 {
    return false
  }
  let seen : Map[Int, Bool] = Map([])
  for child in self.children[id] {
    let tab = self.nodes[child]
    let position = tab.attribute("pos", uri=word_uri).unwrap_or("")
    if tab.uri != word_uri ||
      tab.name != "tab" ||
      !self.children[child].is_empty() ||
      !tab.text.trim().is_empty() ||
      !["left", "right", "center", "decimal", "bar", "clear"].contains(
        tab.attribute("val", uri=word_uri).unwrap_or(""),
      ) ||
      !["none", "dot", "hyphen", "underscore", "heavy", "middleDot"].contains(
        tab.attribute("leader", uri=word_uri).unwrap_or("none"),
      ) ||
      position.is_empty() ||
      !position.iter().all(ch => ch.is_ascii_digit()) ||
      !tab.attributes
      .iter()
      .all(a => a.uri == word_uri && ["pos", "val", "leader"].contains(a.name)) {
      return false
    }
    if tab.attribute("val", uri=word_uri) == Some("bar") &&
      tab.attribute("leader", uri=word_uri).unwrap_or("none") != "none" {
      return false
    }
    let number = @string.parse_int(position[:]) catch { _ => return false }
    if number < 0 || number > 31680 || seen.contains(number) {
      return false
    }
    seen[number] = true
  }
  true
}

///|
fn WordTree::paragraph_tabs(
  self : WordTree,
  id : Int,
  base : Array[@layout.TabStop],
) -> Array[@layout.TabStop] raise @failure.Failure {
  guard self.child(id, "tabs") is Some(tabs) && self.valid_tabs(tabs) else {
    return base
  }
  let values : Map[Int, @layout.TabStop] = Map([])
  for stop in base {
    values[(stop.position * 20).to_int()] = stop
  }
  for child in self.children[tabs] {
    let node = self.nodes[child]
    let position = (@string.parse_int(
      node.attribute("pos", uri=word_uri).unwrap()[:],
    ).to_double() /
    20) catch {
      _ => @failure.reject("invalid-style", "Invalid tab stop position")
    }
    guard position <= 1584 else {
      @failure.reject("invalid-style", "Tab stop exceeds layout range")
    }
    let align = node.attribute("val", uri=word_uri).unwrap()
    if align == "clear" {
      values.remove((position * 20).to_int())
    } else {
      values[(position * 20).to_int()] = {
        position,
        align,
        leader: node.attribute("leader", uri=word_uri).unwrap_or("none"),
      }
    }
  }
  let result = values.values().collect()
  result.sort_by((a, b) => a.position.compare(b.position))
  @layout.validate_tabs(result)
  result
}

///|
fn Session::tab_markup(
  self : Session,
  tree : WordTree,
  paragraph : Int,
  stops : Array[@layout.TabStop],
  style~ : FormatChange[String] = Keep,
) -> String raise @failure.Failure {
  let inherited = self.styles([]).paragraph_style(tree, paragraph, [], style~).tabs
  let values = stops.copy()
  for stop in inherited {
    if !stops.iter().any(other => other.position == stop.position) {
      values.push({ ..stop, align: "clear", })
    }
  }
  values.sort_by((a, b) => a.position.compare(b.position))
  if values.is_empty() {
    return ""
  }
  let out = StringBuilder()
  out.write_string("<od:tabs xmlns:od=\"\{word_uri}\">")
  for stop in values {
    out.write_string(
      "<od:tab od:val=\"\{stop.align}\" od:pos=\"\{(stop.position * 20).to_int()}\" od:leader=\"\{stop.leader}\"/>",
    )
  }
  out.write_string("</od:tabs>")
  out.to_string()
}

///|
fn Styles::paragraph_style(
  self : Styles,
  tree : WordTree,
  id : Int,
  diagnostics : Array[String],
  style~ : FormatChange[String] = Keep,
) -> @layout.Paragraph raise @failure.Failure {
  let props = tree.child(id, "pPr")
  let key = match style {
    Set(key) => Some(key)
    Clear => self.default_paragraph
    Keep =>
      match props.bind(props => tree.value(props, "pStyle")) {
        Some(key) => Some(key)
        None => self.default_paragraph
      }
  }
  let mut paragraph = { ..self.paragraph, id, }
  if key is Some(key) && self.tree is Some(style_tree) {
    for style in self.chain(key, diagnostics) {
      if style_tree.child(style, "pPr") is Some(p) {
        paragraph = paragraph_properties(style_tree, p, paragraph)
      }
    }
  }
  paragraph
}
