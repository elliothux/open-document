///|
let running_rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

///|
fn Session::running_part(
  self : Session,
  tree : WordTree,
  reference : Int32,
  kind : String,
) -> String raise @failure.Failure {
  let node = tree.nodes[reference]
  guard node.uri == word_uri &&
    tree.children[reference].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      (a.uri == word_uri && a.name == "type") ||
      (a.uri == running_rel_uri && a.name == "id")
    }) else {
    @failure.reject("protected-content", "Unknown header or footer reference")
  }
  let id = node.attribute("id", uri=running_rel_uri).unwrap_or("")
  let relations = self
    .relationships()
    .filter(rel => {
      rel.owner == self.main &&
      rel.id == id &&
      rel.kind == running_rel_uri + "/" + kind
    })
  guard relations.length() == 1 && !relations[0].external else {
    @failure.reject(
      "invalid-docx", "Missing or external header or footer relationship",
    )
  }
  relations[0].target
}

///|
fn Session::running_story(
  self : Session,
  part : String,
  kind : String,
  styles : Styles,
  diagnostics : Array[String],
  background : String,
  variant : String,
) -> @layout.RunningStory raise @failure.Failure {
  let tree = WordTree::new(self.part_xml(part))
  guard tree.nodes[0].uri == word_uri &&
    tree.nodes[0].name == (if kind == "header" { "hdr" } else { "ftr" }) &&
    tree.nodes[0].text.trim().is_empty() else {
    @failure.reject("invalid-docx", "Invalid header or footer root")
  }
  let paragraphs : Map[Int32, @layout.Paragraph] = Map([])
  let backgrounds : Map[Int32, String] = Map([])
  let direct : Array[@layout.Paragraph] = []
  let tables : Array[@layout.Table] = []
  let ids = tree.running_nodes()
  for id in ids {
    if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "tbl" {
      // Running pictures need their owning part's relationships, not the body's.
      for
        paragraph in tree
        .descendants(id)
        .filter(p => tree.nodes[p].uri == word_uri && tree.nodes[p].name == "p") {
        self.check_running_paragraph(tree, paragraph)
      }
      tables.push(
        self.table(
          tree,
          styles,
          id,
          direct.length(),
          diagnostics,
          background~,
          running=true,
        ),
      )
      continue
    }
    guard tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p" else {
      @failure.reject(
        "unsupported-layout", "Header or footer objects are unsupported",
      )
    }
    self.check_running_paragraph(tree, id)
    direct.push(
      self.paragraph(tree, styles, id, diagnostics, background~, running=true),
    )
  }
  let story : @layout.RunningStory = { paragraphs: direct, tables, }
  for paragraph in story.all_paragraphs() {
    paragraphs[paragraph.id] = paragraph
    backgrounds[paragraph.id] = background
  }
  self.apply_numbering(tree, styles, paragraphs, backgrounds)
  styles.apply_contextual_spacing(tree, paragraphs)
  story.map_paragraphs(paragraph => {
    ..paragraphs[paragraph.id],
    id: -1 -
    paragraph.id * 6 -
    (if kind == "footer" { 1 } else { 0 }) -
    (if variant == "first" { 2 } else if variant == "even" { 4 } else { 0 }),
    container: if kind == "header" {
      -1
    } else {
      -2
    },
    readOnlyReason: "protected-content:running-area",
  })
}

///|
fn Session::check_running_paragraph(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> Unit raise @failure.Failure {
  tree.check_structure_paragraph(id, running=true)
  let drawings : Set[Int32] = Set([])
  for item in tree.descendants(id) {
    let node = tree.nodes[item]
    if node.uri == word_uri &&
      ["drawing", "pict"].contains(node.name) &&
      !drawings.contains(item) {
      let frame = if node.name == "pict" {
        self.vml_frame(tree, item)
      } else {
        self.drawing_frame(tree, item)
      }
      guard node.name == "pict" ||
        frame.content
        is (@layout.Picture(_, _) | @layout.Shape(_) | @layout.TextBox(_, _)) else {
        @failure.reject(
          "unsupported-layout", "Running chart drawings require support",
        )
      }
      drawings.add(item)
      for child in tree.descendants(item) {
        drawings.add(child)
      }
    }
  }
  for item in tree.descendants(id) {
    if drawings.contains(item) {
      continue
    }
    let node = tree.nodes[item]
    guard node.uri == word_uri &&
      ![
        "drawing", "pict", "object", "bookmarkStart", "bookmarkEnd", "commentReference",
        "commentRangeStart", "commentRangeEnd", "sectPr",
      ].contains(node.name) else {
      @failure.reject(
        "unsupported-layout", "Extended header or footer content is protected",
      )
    }
    if ["br", "cr"].contains(node.name) &&
      node.attribute("type", uri=word_uri).unwrap_or("textWrapping") !=
      "textWrapping" {
      @failure.reject(
        "unsupported-layout", "Page breaks in headers or footers are unsupported",
      )
    }
  }
}

///|
fn Session::running_options(
  self : Session,
  tree : WordTree,
  section : Int32?,
) -> (Bool, Bool) raise @failure.Failure {
  let first = section.bind(id => tree.child(id, "titlePg"))
  if first is Some(id) {
    guard tree.valid_on_off_property(id) else {
      @failure.reject("protected-content", "Invalid first-page setting")
    }
  }
  let different_first = section
    .map(id => tree.character_toggle(id, "titlePg", false, false))
    .unwrap_or(false)
  let different_even = match self.settings_part() {
    None => false
    Some(part) => {
      let settings = WordTree::new(self.part_xml(part))
      if settings.child(0, "evenAndOddHeaders") is Some(id) {
        guard settings.valid_on_off_property(id) else {
          @failure.reject("protected-content", "Invalid even-page setting")
        }
      }
      settings.character_toggle(0, "evenAndOddHeaders", false, false)
    }
  }
  (different_first, different_even)
}

///|
fn Session::running_content(
  self : Session,
  tree : WordTree,
  section : Int32,
  styles : Styles,
  diagnostics : Array[String],
  background : String,
  allVariants~ : Bool = false,
) -> (Map[String, @layout.RunningStory], Map[String, @layout.RunningStory]) raise @failure.Failure {
  let headers = Map([])
  let footers = Map([])
  let seen : Map[String, Bool] = Map([])
  let (first, even) = self.running_options(tree, Some(section))
  for id in tree.children[section] {
    let node = tree.nodes[id]
    if !["headerReference", "footerReference"].contains(node.name) {
      continue
    }
    let kind = if node.name == "headerReference" { "header" } else { "footer" }
    let variant = node.attribute("type", uri=word_uri).unwrap_or("")
    guard ["default", "first", "even"].contains(variant) &&
      !seen.contains(kind + variant) else {
      @failure.reject(
        "invalid-docx", "Duplicate or invalid running area variant",
      )
    }
    seen[kind + variant] = true
    let part = self.running_part(tree, id, kind)
    if !allVariants &&
      ((variant == "first" && !first) || (variant == "even" && !even)) {
      continue
    }
    let story = self.running_story(
      part, kind, styles, diagnostics, background, variant,
    )
    if allVariants || !story.paragraphs.is_empty() || !story.tables.is_empty() {
      (if kind == "header" { headers } else { footers })[variant] = story
    }
  }
  (headers, footers)
}
