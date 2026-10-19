///|
pub(all) struct CopiedNotes {
  comments : String
  vml : String?
}

///|
fn CopiedNotes::read(
  self : CopiedNotes,
  budget~ : @archive.Budget = @archive.Budget::default(),
) -> SheetNotes raise @failure.Failure {
  guard self.comments.length().to_int64() +
    self.vml.map(text => text.length().to_int64()).unwrap_or(0L) <=
    2097152L else {
    @failure.reject("limit-exceeded", "Copied note source exceeds budget")
  }
  let tree = Tree::new(
    @xml.Document::parse(
      @utf8.encode(self.comments),
      "copied-notes",
      budget.xml_depth,
      budget.entry_bytes,
    ),
  )
  let (authors, entries) = read_cell_notes(tree)
  guard !entries.is_empty() &&
    entries.all(note => note.node.attribute("guid") is None) else {
    @failure.reject(
      "protected-content", "Copied notes require independent identities",
    )
  }
  let vml = self.vml.map(text => {
    let tree = Tree::new(
      @xml.Document::parse(
        @utf8.encode(text),
        "copied-note-vml",
        budget.xml_depth,
        budget.entry_bytes,
      ),
    )
    let shapes = vml_note_shapes(tree)
    guard shapes.length() == entries.length() &&
      entries.all(note => shapes.contains(note.address.name())) else {
      @failure.reject(
        "protected-content", "Copied notes and VML anchors do not match",
      )
    }
    ("copied-note-vml", tree, shapes)
  })
  guard vml is Some(_) ||
    entries.all(note => note.node.attribute("shapeId") is None) else {
    @failure.reject(
      "protected-content", "Copied note shape identities require VML",
    )
  }
  { part: "copied-notes", tree, authors, entries, vml, }
}

///|
fn CopiedCells::check_copied_notes(
  self : CopiedCells,
) -> Unit raise @failure.Failure {
  if self.notes is Some(notes) {
    let bounds : Range = {
      top: self.top,
      left: self.left,
      bottom: self.top + self.cells.length() - 1,
      right: self.left + self.cells[0].length() - 1,
    }
    guard notes.read().entries.all(note => bounds.contains(note.address)) else {
      @failure.reject(
        "invalid-operation", "Copied note leaves source rectangle",
      )
    }
  }
}

///|
fn Session::capture_notes(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> CopiedNotes? raise @failure.Failure {
  guard self.read_sheet_notes(sheet) is Some(notes) else { return None }
  let selected = notes.entries.filter(note => range.contains(note.address))
  if selected.is_empty() {
    return None
  }
  let authors : Array[String] = []
  let comments = StringBuilder()
  let shapes = StringBuilder()
  let types : Map[String, Bool] = Map([])
  let mut units = 0L
  for note in selected {
    let author = authors
      .search(note.author)
      .unwrap_or_else(() => {
        let index = authors.length()
        authors.push(note.author)
        index
      })
    let shape_id = note.node
      .attribute("shapeId")
      .map(id => " shapeId=\"\{escaped_attribute(id)}\"")
      .unwrap_or("")
    // Source GUIDs identify the original note; copied legacy notes use their new part/shape identity.
    let markup = "<od:comment ref=\"\{note.address.name()}\" authorId=\"\{author}\"\{shape_id}>\{style_markup(notes.tree, note.body)}</od:comment>"
    units += markup.length().to_int64()
    guard units <= 2097152L else {
      @failure.reject("limit-exceeded", "Copied note source exceeds budget")
    }
    comments.write_string(markup)
    if notes.vml is Some((_, tree, nodes)) {
      let shape = nodes[note.address.name()]
      types[shape.attribute("type").unwrap()[1:].to_owned()] = true
      let markup = style_markup(tree, shape)
      units += markup.length().to_int64()
      guard units <= 2097152L else {
        @failure.reject("limit-exceeded", "Copied note source exceeds budget")
      }
      shapes.write_string(markup)
    }
  }
  let names = StringBuilder()
  for author in authors {
    let markup = "<od:author>\{encode_text(author)}</od:author>"
    units += markup.length().to_int64()
    guard units <= 2097152L else {
      @failure.reject("limit-exceeded", "Copied note source exceeds budget")
    }
    names.write_string(markup)
  }
  let comments = "<od:comments xmlns:od=\"\{spreadsheet_uri}\"><od:authors>\{names.to_string()}</od:authors><od:commentList>\{comments.to_string()}</od:commentList></od:comments>"
  let vml = notes.vml.map(value => {
    let (_, tree, _) = value
    let definitions = StringBuilder()
    for node in tree.document.nodes() {
      if node.uri == note_vml_uri &&
        node.name == "shapetype" &&
        types.contains(node.attribute("id").unwrap_or("")) {
        let markup = style_markup(tree, node)
        units += markup.length().to_int64()
        guard units <= 2097152L else {
          @failure.reject("limit-exceeded", "Copied note source exceeds budget")
        }
        definitions.write_string(markup)
      }
    }
    "<xml>\{definitions.to_string()}\{shapes.to_string()}</xml>"
  })
  Some(CopiedNotes::{ comments, vml, })
}

///|
fn Session::prepare_copied_notes(
  self : Session,
  plan : CellEditPlan,
  index : Int,
  target : Range,
  copied : CopiedCells,
  transpose : Bool,
) -> Unit raise @failure.Failure {
  let sheet = plan.sheets[index]
  let candidate = { ..self, parts: plan.parts, }
  if candidate.read_sheet_notes(sheet) is Some(notes) {
    let removed : Map[String, Address?] = Map([])
    for note in notes.entries {
      if target.contains(note.address) {
        removed[note.address.name()] = None
      }
    }
    update_note_addresses(notes, removed, plan.parts, plan.edits)
  }
  if copied.notes is Some(notes) {
    let incoming = notes.read(budget=self.budget)
    let destinations = Map::from_array(
      incoming.entries.map(note => {
        let point = copied.rule_range(
          {
            top: note.address.row,
            bottom: note.address.row,
            left: note.address.column,
            right: note.address.column,
          },
          target,
          transpose,
        )
        (note.address.name(), Address::{ row: point.top, column: point.left, })
      }),
    )
    let document = self.insert_note_fragments(
      sheet,
      sheet.document,
      incoming,
      destinations,
      plan.parts,
      plan.edits,
      plan.created_parts,
    )
    plan.sheets[index] = Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      plan.styles.length(),
    )
  }
}
