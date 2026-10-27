///|
fn theme_font_node(
  tree : WordTree,
  kind : String,
  script : String,
) -> Int raise @failure.Failure {
  let elements = theme_child(tree, 0, "themeElements")
  let scheme = theme_child(tree, elements, "fontScheme")
  let parent = theme_child(tree, scheme, kind + "Font")
  let id = theme_child(tree, parent, script)
  let node = tree.nodes[id]
  let source = tree.source[node.start:node.end]
  guard tree.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      ["typeface", "panose", "pitchFamily", "charset"].contains(a.name)
    }) else {
    @failure.reject("protected-content", "Extended theme font is protected")
  }
  id
}

///|
pub fn Session::theme_fonts(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let reason = self.theme_edit_reason()
  let document = match self.theme_part() {
    Some(part) => self.part_xml(part)
    None =>
      @xml.Document::parse(
        @utf8.encode(blank_word_theme()),
        "",
        self.opc.budget.xml_depth,
        self.opc.budget.entry_bytes,
      )
  }
  let tree = WordTree::new(document)
  let fonts : Array[Json] = []
  for kind in ["major", "minor"] {
    for script in ["latin", "ea", "cs"] {
      fonts.push(
        {
          "kind": Json(kind),
          "script": Json(script),
          "font": Json(
            tree.nodes[theme_font_node(tree, kind, script)]
            .attribute("typeface")
            .unwrap_or(""),
          ),
          "reason": Json(reason),
        } catch {
          @failure.Failure(message~, ..) =>
            {
              "kind": Json(kind),
              "script": Json(script),
              "font": Json::null(),
              "reason": Json(message),
            }
        },
      )
    }
  }
  { "revision": revision, "fonts": Json(fonts) }
}

///|
fn flow_font_keys(flow : @layout.Flow) -> Map[String, Array[String]] {
  let keys : Map[String, Array[String]] = Map([])
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    paragraphs.append(table.rows.flatten().flatten())
  }
  let groups = [("body", paragraphs)]
  for note in flow.notes {
    groups.push((note.kind + note.key, note.content))
  }
  for (kind, stories) in [("header", flow.headers), ("footer", flow.footers)] {
    for variant, paragraphs in stories {
      groups.push((kind + variant, paragraphs))
    }
  }
  for (scope, paragraphs) in groups {
    let nested = paragraphs
      .iter()
      .flat_map(p => p.spans.iter())
      .flat_map(s => {
        match s.drawing {
          Some({ content: @layout.TextBox(_, text), .. }) =>
            text.paragraphs().iter()
          _ => [].iter()
        }
      })
      .collect()
    for p in paragraphs + nested {
      let fonts = p.spans.filter(s => s.drawing is None).map(s => s.style.font)
      if p.marker is Some(marker) {
        fonts.push(marker.style.font)
      }
      keys[scope + ":" + p.id.to_string()] = fonts
    }
  }
  keys
}

///|
pub(all) struct ThemeFontEdit {
  kind : String
  script : String
  font : String
}

///|
pub fn Session::set_theme_fonts(
  self : Session,
  revision : Int,
  fonts : Array[ThemeFontEdit],
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard !fonts.is_empty() && fonts.length() <= 6 else {
    @failure.reject(
      "invalid-operation", "Expected one to six theme font changes",
    )
  }
  let seen : Map[(String, String), Bool] = Map([])
  for change in fonts {
    let font = change.font
    guard ["major", "minor"].contains(change.kind) &&
      ["latin", "ea", "cs"].contains(change.script) &&
      !(change.script == "latin" && font.is_empty()) &&
      !seen.contains((change.kind, change.script)) else {
      @failure.reject(
        "invalid-operation", "Invalid or duplicate theme font slot",
      )
    }
    seen[(change.kind, change.script)] = true
    if !font.is_empty() {
      CharacterFormat::new(family=Set(font)).validate()
    }
    guard !font.has_prefix("+") &&
      !font.contains("|") &&
      !font.contains("\n") &&
      !font.contains("\r") else {
      @failure.reject(
        "invalid-operation", "Theme fonts require physical font families",
      )
    }
  }
  let reason = self.theme_edit_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let original = self.theme_part()
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = match original {
    Some(part) => part
    None => self.new_word_part("theme", parts, edits, created)
  }
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let tree = WordTree::new(document)
  let changes : Array[@xml.SourceChange] = []
  for change in fonts {
    let value = change.font
    let node = tree.nodes[theme_font_node(tree, change.kind, change.script)]
    if node.attribute("typeface") == Some(value) {
      continue
    }
    let escaped = property_attribute(value)
    changes.push(
      if node.attributes
        .iter()
        .find_first(a => a.uri.is_empty() && a.name == "typeface")
        is Some(attr) {
        {
          node: node.id,
          offset: attr.start - node.start,
          length: attr.end - attr.start,
          xml: escaped,
        }
      } else {
        {
          node: node.id,
          offset: node.opening_end -
          node.start -
          (if node.empty { 2 } else { 1 }),
          length: 0,
          xml: " typeface=\"\{escaped}\"",
        }
      },
    )
  }
  if changes.is_empty() && original is Some(_) {
    return self.edit_state()
  }
  let (candidate, edit) = document.edit_source(changes)
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  let view = { ..self, parts, }
  let after = flow_font_keys(view.flow())
  let before = flow_font_keys(self.flow())
  let checked : Map[String, Bool] = Map([])
  for id, keys in after {
    if before.get(id) == Some(keys) {
      continue
    }
    for key in keys {
      if checked.contains(key) {
        continue
      }
      checked[key] = true
      guard @layout.font_profile_identity(profile, key) is Some(identity) else {
        @failure.reject("missing-font", "Missing theme font profile: " + key)
      }
      ignore(probe.font_index(identity))
    }
  }
  let tree = WordTree::new(self.document())
  let paragraphs = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes: xml_part_edit_bytes(edits, created),
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
