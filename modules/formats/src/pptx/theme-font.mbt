///|
fn theme_font_script(script : String) -> Bool {
  ["latin", "ea", "cs"].contains(script) ||
  (
    script.length() == 4 &&
    script[0] >= 65 &&
    script[0] <= 90 &&
    script[1:].iter().all(c => c >= 'a' && c <= 'z')
  )
}

///|
fn theme_font_parent(tree : Tree, kind : String) -> Ref raise @failure.Failure {
  let elements = tree.required(
    tree.root("theme", uri=drawing_uri).id,
    "themeElements",
  )
  let scheme = tree.required(elements.id, "fontScheme")
  { tree, node: tree.required(scheme.id, kind + "Font"), }
}

///|
fn theme_font_source(
  parent : Ref,
  script : String,
) -> Ref? raise @failure.Failure {
  let matches = parent.tree.children
    .get(parent.node.id)
    .unwrap_or([])
    .filter(node => {
      node.uri == drawing_uri &&
      (if ["latin", "ea", "cs"].contains(script) {
        node.name == script
      } else {
        node.name == "font" && node.attribute("script") == Some(script)
      })
    })
  guard matches.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate theme font slot")
  }
  guard matches is [node] else { return None }
  let source : Ref = { tree: parent.tree, node, }
  let markup = source_xml(source)
  guard node.text.trim().is_empty() &&
    !markup.contains("<!--") &&
    !markup.contains("<?") &&
    parent.tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        ["typeface", "panose", "pitchFamily", "charset"].contains(a.name) ||
        (node.name == "font" && a.name == "script")
      )
    }) else {
    @failure.reject("protected-content", "Extended theme font is protected")
  }
  Some(source)
}

///|
fn Session::theme_fonts(self : Session) -> Json raise @failure.Failure {
  let trees = self.theme_trees()
  let scripts : Array[String] = ["latin", "ea", "cs"]
  for tree in trees {
    for kind in ["major", "minor"] {
      let parent = theme_font_parent(tree, kind)
      for node in tree.all(parent.node.id, "font") {
        if node.attribute("script") is Some(script) &&
          theme_font_script(script) &&
          !scripts.contains(script) {
          scripts.push(script)
        }
      }
    }
  }
  guard scripts.length() <= 128 else {
    @failure.reject("limit-exceeded", "Theme font slots exceed 256")
  }
  let values : Array[Json] = []
  for kind in ["major", "minor"] {
    for script in scripts {
      let mut value : String? = None
      let mut mixed = false
      let mut reason = ""
      for tree in trees {
        try {
          let source = theme_font_source(theme_font_parent(tree, kind), script)
          let current = source
            .bind(s => s.node.attribute("typeface"))
            .unwrap_or("")
          if value is Some(previous) && current != previous {
            mixed = true
          }
          value = Some(current)
        } catch {
          @failure.Failure(message~, ..) => reason = message
        }
      }
      values.push({
        "kind": kind,
        "script": script,
        "font": if mixed {
          Json::null()
        } else {
          value.map(Json::string).unwrap_or(Json::null())
        },
        "reason": reason,
      })
    }
  }
  Json(values)
}

///|
fn theme_font_change(
  parent : Ref,
  script : String,
  font : String,
) -> @xml.SourceChange? raise @failure.Failure {
  if theme_font_source(parent, script) is Some(source) {
    if source.node.attribute("typeface").unwrap_or("") == font {
      return None
    }
    return Some(attribute_change(source, "typeface", xml_attribute(font)))
  }
  if font.is_empty() {
    return None
  }
  let core = ["latin", "ea", "cs"]
  let markup = if core.contains(script) {
    "<a:\{script} xmlns:a=\"\{drawing_uri}\" typeface=\"\{xml_attribute(font)}\"/>"
  } else {
    "<a:font xmlns:a=\"\{drawing_uri}\" script=\"\{script}\" typeface=\"\{xml_attribute(font)}\"/>"
  }
  let rank = core.search(script).unwrap_or(3)
  for node in parent.tree.children.get(parent.node.id).unwrap_or([]) {
    let next = core
      .search(node.name)
      .unwrap_or(if node.name == "font" { 3 } else { 4 })
    if node.uri == drawing_uri && next > rank {
      return Some({
        node: parent.node.id,
        offset: node.start - parent.node.start,
        length: 0,
        xml: markup,
      })
    }
  }
  Some(insertion(parent.node, markup))
}

///|
fn Session::set_theme_font(
  self : Session,
  kind : String,
  script : String,
  font : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard ["major", "minor"].contains(kind) &&
    theme_font_script(script) &&
    (script != "latin" || !font.is_empty()) else {
    @failure.reject("invalid-operation", "Invalid theme font slot")
  }
  if !font.is_empty() {
    ignore(TextFormat::new(font~).normalized())
  }
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  for tree in self.theme_trees() {
    if theme_font_change(theme_font_parent(tree, kind), script, font)
      is Some(change) {
      let (document, edit) = tree.document.edit_source([change])
      parts[tree.part] = document
      edits.push((tree.part, edit))
    }
  }
  if edits.is_empty() {
    return self.query()
  }
  let candidates = self.slides.mapi((index, slide) => {
    read_slide(
      self.opc,
      self.main,
      self.cache,
      slide.tree,
      index~,
      parts~,
      date_time=self.date_time,
    )
  })
  ignore(slide_font_keys(candidates))
  let seen : Map[String, Bool] = Map([])
  let changes : Map[String, (Tree, Array[@xml.SourceChange])] = Map([])
  for i, slide in candidates {
    for j, object in slide.objects {
      if seen.contains(object.id) || object.paragraphs.is_empty() {
        continue
      }
      seen[object.id] = true
      let keys = slide_font_keys([{ ..slide, objects: [object], }])
      if keys ==
        slide_font_keys([
          { ..self.slides[i], objects: [self.slides[i].objects[j]], },
        ]) {
        continue
      }
      for key in keys {
        guard profile.get(key) is Some(identity) else {
          @failure.reject("missing-font", "Missing theme font profile: " + key)
        }
        ignore(probe.font_index(identity))
      }
      let updates = derived_frame_changes(object, probe, profile)
      if !updates.is_empty() {
        let entry = changes.get_or_init(object.source.tree.part, () => {
          (object.source.tree, [])
        })
        entry.1.append(updates)
      }
    }
  }
  let documents : Map[String, @xml.Document] = Map([])
  for part, (tree, updates) in changes {
    let (document, edit) = tree.document.edit_source(updates)
    documents[part] = document
    if !self.slides.any(slide => slide.tree.part == part) {
      parts[part] = document
    }
    edits.push((part, edit))
  }
  let slides = self.slides.mapi((index, slide) => {
    let tree = documents
      .get(slide.tree.part)
      .map(document => Tree::new(slide.tree.part, document))
      .unwrap_or(slide.tree)
    read_slide(
      self.opc,
      self.main,
      self.cache,
      tree,
      index~,
      parts~,
      date_time=self.date_time,
    )
  })
  self.commit_slides(self.main, slides, edits, self.selection, parts~)
  self.query()
}
