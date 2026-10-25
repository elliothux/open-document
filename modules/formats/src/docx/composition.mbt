///|
priv struct Composition {
  id : Int
  selection : Selection
  prepared : PreparedEdit?
}

///|
/// Requires an open session with no pending composition before persistence or editing.
pub fn Session::check_idle(self : Session) -> Unit raise @failure.Failure {
  ignore(self.document())
  guard self.composition is None && self.drawing_gesture is None else {
    @failure.reject(
      "busy", "Complete or cancel composition or drawing gesture before this operation",
    )
  }
}

///|
fn Session::display_document(
  self : Session,
) -> @xml.Document raise @failure.Failure {
  let original = self.document()
  if self.drawing_gesture is Some({ prepared: Some(prepared), .. }) {
    return prepared.document
  }
  match self.composition {
    Some({ prepared: Some(prepared), .. }) => prepared.document
    _ => original
  }
}

///|
fn Session::check_composition(
  self : Session,
  revision : Int,
  id : Int,
) -> Composition raise @failure.Failure {
  self.check_revision_value(revision)
  guard self.composition is Some(composition) && composition.id == id else {
    @failure.reject(
      "stale-composition", "Composition id does not match current session",
    )
  }
  composition
}

///|
fn Session::prepare_composition(
  self : Session,
  composition : Composition,
  text : String,
) -> PreparedEdit? raise @failure.Failure {
  guard !text.contains("\n") else {
    @failure.reject("invalid-operation", "Composition must not contain LF")
  }
  if text.is_empty() {
    return None
  }
  self.prepare_range(composition.selection, text)
}

///|
/// Begins one tentative replacement at the current selection without changing history.
pub fn Session::begin_composition(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-operation", "Composition requires a selection")
  }
  let tree = WordTree::new(self.document())
  if selection.anchor.paragraph == selection.focus.paragraph &&
    tree.has_text_revisions(selection.anchor.paragraph) {
    self.check_position(selection.anchor)
    self.check_position(selection.focus)
  } else if self.table_cell_range(
      tree,
      selection,
      pictures=true,
      fields=true,
      math=true,
      notes=true,
    )
    is None {
    ignore(
      self.paragraph_range_in(
        self.document(),
        tree,
        selection,
        structural=selection.anchor.paragraph != selection.focus.paragraph,
        sectionBoundary=true,
        fields=true,
        math=true,
        tables=true,
        notes=true,
      ),
    )
  }
  guard self.composition_id < 0x7fffffff else {
    @failure.reject("limit-exceeded", "Composition identity exhausted")
  }
  self.composition_id += 1
  self.composition = Some({
    id: self.composition_id,
    selection,
    prepared: None,
  })
  self.input_group = None
  self.typing_text = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.edit_state()
}

///|
/// Replaces the current preview from the original range; failed updates keep the last preview.
pub fn Session::update_composition(
  self : Session,
  revision : Int,
  id : Int,
  text : String,
) -> Json raise @failure.Failure {
  let composition = self.check_composition(revision, id)
  let prepared = self.prepare_composition(composition, text)
  if prepared is Some(candidate) {
    let (parts, _, bytes) = self.note_transition(candidate.document, self.parts)
    guard bytes <= history_byte_limit - candidate.edit.bytes else {
      @failure.reject(
        "limit-exceeded", "Note composition exceeds history budget",
      )
    }
    self.opc.validate_changes(self.replacements(candidate.document, parts))
    if candidate.document
      .nodes()
      .any(node => node.uri == word_shape_uri && node.name == "txbx") {
      ignore(self.flow_from(candidate.document))
    }
  }
  self.composition = Some({ ..composition, prepared, })
  self.edit_result(prepared.map(edit => edit.edit.paragraphs).unwrap_or([]))
}

///|
/// Commits authoritative final text as at most one edit; empty text cancels.
pub fn Session::commit_composition(
  self : Session,
  revision : Int,
  id : Int,
  text : String,
) -> Json raise @failure.Failure {
  let composition = self.check_composition(revision, id)
  let prepared = self.prepare_composition(composition, text)
  if prepared is Some(prepared) {
    if prepared.edit.bytes == 0 {
      self.composition = None
      return self.select(revision, prepared.edit.after.unwrap())
    }
    self.commit_edit(prepared.edit, prepared.document, tracking_edit=true)
    self.typing_text = prepared.typing_text
  }
  self.composition = None
  self.edit_result(prepared.map(edit => edit.edit.paragraphs).unwrap_or([]))
}

///|
/// Discards the tentative document and retains committed selection, revision and history.
pub fn Session::cancel_composition(
  self : Session,
  revision : Int,
  id : Int,
) -> Json raise @failure.Failure {
  let composition = self.check_composition(revision, id)
  self.composition = None
  self.edit_result(
    composition.prepared.map(edit => edit.edit.paragraphs).unwrap_or([]),
  )
}
