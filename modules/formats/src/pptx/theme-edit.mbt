///|
let theme_color_slots : Array[String] = [
  "dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5",
  "accent6", "hlink", "folHlink",
]

///|
fn Session::theme_trees(self : Session) -> Array[Tree] raise @failure.Failure {
  let themes : Map[String, Tree] = Map([])
  for slide in self.slides {
    let layout = slide_layout(self.opc, slide.tree.part, self.parts).unwrap()
    let master = relation(self.opc, layout, "slideMaster").unwrap()
    let theme = relation(self.opc, master, "theme").unwrap()
    if !themes.contains(theme) {
      themes[theme] = load_tree(self.opc, self.cache, theme, parts=self.parts)
    }
  }
  themes.values().to_array()
}

///|
fn theme_color_source(
  theme : Theme,
  slot : String,
) -> Ref raise @failure.Failure {
  let tree = theme.tree
  let root = tree.root("theme", uri=drawing_uri)
  let elements = tree.required(root.id, "themeElements")
  let scheme = tree.required(elements.id, "clrScheme")
  let node = tree.required(scheme.id, slot)
  let children = tree.children.get(node.id).unwrap_or([])
  let markup = tree.document.source()[node.start:node.end]
  guard node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    !markup.contains("<!--") &&
    !markup.contains("<?") &&
    children is [child] &&
    child.uri == drawing_uri &&
    ["srgbClr", "sysClr"].contains(child.name) &&
    child.text.trim().is_empty() &&
    tree.children.get(child.id).unwrap_or([]).is_empty() &&
    child.attributes.all(a => {
      a.uri.is_empty() &&
      (a.name == "val" || (child.name == "sysClr" && a.name == "lastClr"))
    }) else {
    @failure.reject(
      "protected-content",
      "Extended theme color is protected",
      part=tree.part,
    )
  }
  { tree, node, }
}

///|
fn Session::theme_colors(self : Session) -> Json raise @failure.Failure {
  let themes = self.theme_trees().map(tree => read_theme(tree, []))
  Json(
    theme_color_slots.map(slot => {
      let mut value : String? = None
      let mut mixed = false
      let mut reason = ""
      for theme in themes {
        try {
          let source = theme_color_source(theme, slot)
          let current = color(theme, source)
          if value is Some(previous) && previous != current {
            mixed = true
          }
          value = Some(current)
        } catch {
          @failure.Failure(message~, ..) => reason = message
        }
      }
      {
        "slot": Json(slot),
        "color": if mixed {
          Json::null()
        } else {
          value.map(Json::string).unwrap_or(Json::null())
        },
        "reason": Json(reason),
      }
    }),
  )
}

///|
fn Session::set_theme_color(
  self : Session,
  slot : String,
  value : String,
) -> Json raise @failure.Failure {
  guard theme_color_slots.contains(slot) else {
    @failure.reject("invalid-operation", "Invalid theme color slot")
  }
  guard value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject(
      "invalid-operation", "Theme colors require six hexadecimal digits",
    )
  }
  let value = value.to_lower()
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  for tree in self.theme_trees() {
    let theme = read_theme(tree, [])
    let source = theme_color_source(theme, slot)
    if color(theme, source) == value {
      continue
    }
    let child = tree.children[source.node.id][0]
    let (document, edit) = tree.document.edit_source([
      {
        node: source.node.id,
        offset: child.start - source.node.start,
        length: child.end - child.start,
        xml: "<a:srgbClr xmlns:a=\"\{drawing_uri}\" val=\"\{value}\"/>",
      },
    ])
    parts[tree.part] = document
    edits.push((tree.part, edit))
  }
  if edits.is_empty() {
    return self.query()
  }
  let slides = self.slides.mapi((index, slide) => {
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
  self.commit_slides(self.main, slides, edits, self.selection, parts~)
  self.query()
}
