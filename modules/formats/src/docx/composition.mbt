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
  guard self.composition is None else {
    @failure.reject(
      "busy", "Complete or cancel composition before this operation",
    )
  }
}

///|
fn Session::display_document(
  self : Session,
) -> @xml.Document raise @failure.Failure {
  let original = self.document()
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
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-operation", "Composition requires a selection")
  }
  ignore(
    self.paragraph_range(
      WordTree::new(self.document()),
      selection,
      structural=selection.anchor.paragraph != selection.focus.paragraph,
    ),
  )
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
    self.opc.validate_replacements(
      Map::from_array([(self.main, candidate.document.bytes())]),
    )
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
    self.commit_edit(prepared.edit, prepared.document)
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
