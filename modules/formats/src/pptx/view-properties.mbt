///|
fn slide_view_markup(visible : Bool, guides : Array[Guide]) -> String {
  "<od:cSldViewPr xmlns:od=\"\{presentation_uri}\" showGuides=\"\{if visible { "1" } else { "0" }}\"><od:cViewPr><od:scale xmlns:a=\"\{drawing_uri}\"><a:sx n=\"1\" d=\"1\"/><a:sy n=\"1\" d=\"1\"/></od:scale><od:origin x=\"0\" y=\"0\"/></od:cViewPr>\{guides_markup(guides)}</od:cSldViewPr>"
}

///|
fn insert_slide_view(
  tree : Tree,
  body : String,
) -> @xml.SourceChange raise @failure.Failure {
  let root = tree.root("viewPr")
  if tree.one(root.id, "slideViewPr", uri=presentation_uri) is Some(view) {
    insertion(view, body)
  } else {
    let markup = "<od:slideViewPr xmlns:od=\"\{presentation_uri}\">\{body}</od:slideViewPr>"
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        [
          "outlineViewPr", "notesTextViewPr", "sorterViewPr", "notesViewPr", "gridSpacing",
          "extLst",
        ].contains(node.name)
      })
    if next is Some(next) {
      {
        node: root.id,
        offset: next.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    }
  }
}

///|
fn Session::commit_view_properties(
  self : Session,
  tree : Tree?,
  changes : Array[@xml.SourceChange],
  body : String,
  spacing~ : Double? = None,
) -> Json raise @failure.Failure {
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  if tree is Some(tree) {
    let mut document = tree.document
    if !changes.is_empty() {
      let (updated, edit) = document.edit_source(changes)
      document = updated
      edits.push((tree.part, edit))
    }
    if spacing is Some(spacing) {
      let current = Tree::new(tree.part, document)
      let (updated, edit) = document.edit_source(
        grid_spacing_changes(current, spacing),
      )
      document = updated
      edits.push((tree.part, edit))
    }
    parts[tree.part] = document
  } else {
    let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
    ignore(segments.pop())
    let directory = segments.join("/")
    let links = self.relationships()
    let mut identity = 1
    let mut path = ""
    for ;; {
      path = (if directory.is_empty() { "" } else { directory + "/" }) +
        "odViewProps\{identity}.xml"
      if !self.opc.names.contains(path.to_lower()) &&
        !parts.contains(path) &&
        !links.any(link => {
          link.owner == self.main.part && link.id == "odViewProps\{identity}"
        }) {
        break
      }
      identity += 1
      guard identity <= self.budget.entries else {
        @failure.reject(
          "limit-exceeded", "View properties identity budget exceeded",
        )
      }
    }
    let document = @xml.Document::parse(
      @utf8.encode(
        "<p:viewPr xmlns:p=\"\{presentation_uri}\"><p:slideViewPr>\{body}</p:slideViewPr>\{spacing.map(grid_spacing_markup).unwrap_or("")}</p:viewPr>",
      ),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    parts[path] = document
    created[path] = document
    for
      (owner, markup) in [
        (
          relationship_part(self.main.part),
          "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"odViewProps\{identity}\" Type=\"\{relationship_uri}/viewProps\" Target=\"/\{xml_attribute(path)}\"/>",
        ),
        (
          "[Content_Types].xml",
          "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(path)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml\"/>",
        ),
      ] {
      let original = self.part_document(owner)
      let (document, edit) = original.edit_source([
        insertion(original.nodes()[0], markup),
      ])
      parts[owner] = document
      edits.push((owner, edit))
    }
  }
  self.commit_slides(
    self.main,
    self.slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
