///|
pub(all) struct CopiedNotes {
  comments : String
  vml : String?
  threads : String?
  people : String?
}

///|
fn CopiedNotes::read(
  self : CopiedNotes,
  budget~ : @archive.Budget = @archive.Budget::default(),
) -> SheetNotes raise @failure.Failure {
  guard self.comments.length().to_int64() +
    self.vml.map(text => text.length().to_int64()).unwrap_or(0L) +
    self.threads.map(text => text.length().to_int64()).unwrap_or(0L) +
    self.people.map(text => text.length().to_int64()).unwrap_or(0L) <=
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
  let (authors, entries) = read_cell_notes(tree, threaded=true)
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
  let notes = { part: "copied-notes", tree, authors, entries, vml, }
  check_thread_notes(Some(notes), self.read_threads(budget~))
  notes
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
  guard self.read_sheet_notes(sheet, allow_threads=true) is Some(notes) else {
    return None
  }
  let native = self.read_sheet_threads(sheet)
  check_thread_notes(Some(notes), native)
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
    let revision = note.node
      .attribute(
        "uid",
        uri="http://schemas.microsoft.com/office/spreadsheetml/2014/revision",
      )
      .map(id => {
        " xmlns:xr=\"http://schemas.microsoft.com/office/spreadsheetml/2014/revision\" xr:uid=\"\{escaped_attribute(id)}\""
      })
      .unwrap_or("")
    // Source GUIDs identify the original note; copied legacy notes use their new part/shape identity.
    let markup = "<od:comment ref=\"\{note.address.name()}\" authorId=\"\{author}\"\{shape_id}\{revision}>\{style_markup(notes.tree, note.body)}</od:comment>"
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
  let (threads, people) = copied_thread_source(native, range, units~)
  Some(CopiedNotes::{ comments, vml, threads, people, })
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
  let candidate = { ..self, parts: plan.parts.copy(), }
  let previous = candidate.read_sheet_threads(sheet)
  if candidate.read_sheet_notes(sheet, allow_threads=true) is Some(notes) {
    let removed : Map[String, Address?] = Map([])
    for note in notes.entries {
      if target.contains(note.address) {
        removed[note.address.name()] = None
      }
    }
    update_note_addresses(notes, removed, plan.parts, plan.edits, threaded=true)
    update_thread_addresses(previous, removed, plan.parts, plan.edits)
  }
  if copied.notes is Some(notes) {
    let incoming = notes.read(budget=self.budget)
    let native = notes.read_threads(budget=self.budget)
    let people = matching_thread_people(native, previous)
    let ids = self.copied_thread_ids(
      native,
      Some(incoming),
      new_people=native.people
        .filter(p => !people.contains(p.id))
        .map(p => p.id),
    )
    self.prepare_thread_people(
      native,
      previous,
      people,
      ids,
      plan.parts,
      plan.created_parts,
      plan.edits,
    )
    let incoming = remap_copied_notes(incoming, ids)
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
      threaded=true,
    )
    plan.sheets[index] = Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      plan.styles.length(),
    )
    let candidate = { ..self, parts: plan.parts.copy(), }
    let roster = candidate.read_sheet_threads(plan.sheets[index])
    self.insert_thread_fragments(
      plan.sheets[index],
      remap_copied_threads(native, ids, people, roster),
      destinations,
      plan.parts,
      plan.edits,
      plan.created_parts,
    )
  }
  let complete = { ..self, parts: plan.parts, }
  complete.check_thread_fallbacks(
    plan.sheets[index],
    complete.read_sheet_threads(plan.sheets[index]),
  )
}
