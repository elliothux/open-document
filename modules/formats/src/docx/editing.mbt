///|
let history_entry_limit = 100

///|
let history_byte_limit = 4194304

///|
let command_limit = 65536

///|
pub(all) struct Position {
  paragraph : Int
  offset : Int
  affinity : String
  bidiLevel : Int?
  frameStart : Int?
} derive(Eq)

///|
pub impl ToJson for Position with fn to_json(self) -> Json {
  let fields = {
    "paragraph": Json(self.paragraph),
    "offset": Json(self.offset),
    "affinity": Json(self.affinity),
  }
  if self.bidiLevel is Some(level) {
    fields["bidiLevel"] = Json(level)
  }
  if self.frameStart is Some(start) {
    fields["frameStart"] = Json(start)
  }
  Json::object(fields)
}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend Position with ToJson::{to_json}

///|
pub(all) struct Selection {
  anchor : Position
  focus : Position
} derive(Eq, ToJson)

///|
pub extend Selection with Eq::{equal, not_equal}

///|
pub extend Selection with ToJson::{to_json}

///|
priv struct Edit {
  xml : Array[@xml.Edit]
  before : Selection?
  after : Selection?
  paragraphs : Array[Int]
  bytes : Int
}

///|
priv struct PreparedEdit {
  edit : Edit
  document : @xml.Document
  typing_text : Int?
  join_group : Bool
}

///|
fn Session::editable_texts(
  self : Session,
  paragraph : Int,
) -> Array[TextNode] raise @failure.Failure {
  WordTree::new(self.document()).check_editable_paragraph(
    paragraph,
    part=self.main,
  )
  self.texts.filter(node => node.paragraph == paragraph)
}

///|
fn validate_position(
  position : Position,
  boundaries : Array[Int],
) -> Unit raise @failure.Failure {
  if position.frameStart is Some(start) &&
    (start <= position.offset || !boundaries.contains(start)) {
    @failure.reject("invalid-position", "Invalid preferred frame boundary")
  }
  if position.bidiLevel is Some(level) && (level < 0 || level > 126) {
    @failure.reject("invalid-position", "Invalid cursor direction level")
  }
  guard (position.affinity == "before" || position.affinity == "after") &&
    boundaries.contains(position.offset) else {
    @failure.reject(
      "invalid-position", "Position must be an extended grapheme boundary",
    )
  }
}

///|
fn Session::check_revision(
  self : Session,
  revision : Int,
) -> Unit raise @failure.Failure {
  self.check_revision_value(revision)
  self.check_idle()
}

///|
fn Session::check_revision_value(
  self : Session,
  revision : Int,
) -> Unit raise @failure.Failure {
  ignore(self.document())
  guard self.revision == revision else {
    @failure.reject("stale-revision", "Revision does not match current session")
  }
}

///|
fn Session::edit_result(
  self : Session,
  affected : Array[Int],
) -> Json raise @failure.Failure {
  ignore(self.document())
  let current = match self.composition {
    Some({ prepared: Some(prepared), .. }) => prepared.edit.after
    _ => self.selection
  }
  let selection : Json = match current {
    None => Json::null()
    Some(selection) => selection.to_json()
  }
  {
    "revision": self.revision,
    "selection": selection,
    "canUndo": !self.history.is_empty(),
    "canRedo": !self.redo.is_empty(),
    "affectedParagraphs": affected,
    "historyBytes": self.history_bytes,
    "historyEntries": self.history.length() + self.redo.length(),
    "historyEntryLimit": history_entry_limit,
    "historyByteLimit": history_byte_limit,
    "commandLimit": command_limit,
    "compositionId": self.composition
    .map(composition => Json(composition.id))
    .unwrap_or(Json::null()),
  }
}

///|
pub fn Session::edit_state(self : Session) -> Json raise @failure.Failure {
  self.edit_result([])
}

///|
pub fn Session::select(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  for position in [selection.anchor, selection.focus] {
    self.check_position(position)
  }
  self.selection = Some(selection)
  self.input_group = None
  self.typing_text = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.edit_state()
}

///|
/// Validates a logical editing position without changing selection or revision.
pub fn Session::check_position(
  self : Session,
  position : Position,
) -> Unit raise @failure.Failure {
  self.check_position_in(self.display_document(), position)
}

///|
fn Session::check_position_in(
  self : Session,
  document : @xml.Document,
  position : Position,
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  tree.check_editable_paragraph(position.paragraph, part=self.main)
  let nodes = tree.nodes
  let texts = docx_texts(tree).filter(node => {
    node.paragraph == position.paragraph
  })
  let text = texts.map(node => nodes[node.id].text).join("")
  validate_position(position, @layout.grapheme_boundaries(text))
}

///|
/// Replaces a logical range atomically; LF separators create ordinary paragraphs.
/// A positive input group joins continuous ordinary input at the confirmed caret.
pub fn Session::replace_range(
  self : Session,
  revision : Int,
  selection : Selection,
  text : String,
  input_group~ : Int? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let prepared = self.prepare_range(selection, text, input_group~)
  if prepared is Some(prepared) {
    self.commit_edit(
      prepared.edit,
      prepared.document,
      input_group~,
      join_group=prepared.join_group,
    )
    self.typing_text = prepared.typing_text
    self.edit_result(prepared.edit.paragraphs)
  } else {
    if input_group is None {
      self.input_group = None
    }
    self.edit_state()
  }
}

///|
fn Session::prepare_range(
  self : Session,
  selection : Selection,
  text : String,
  input_group~ : Int? = None,
) -> PreparedEdit? raise @failure.Failure {
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Command input exceeds UTF-16 budget")
  }
  guard @xml.valid_text(text) && !text.contains("\r") && !text.contains("\t") else {
    @failure.reject(
      "invalid-operation", "Paragraph input must be valid XML text without CR or tab",
    )
  }
  let anchor = selection.anchor
  let focus = selection.focus
  if input_group is Some(group) {
    guard group > 0 && !text.is_empty() && !text.contains("\n") else {
      @failure.reject(
        "invalid-operation", "Input group requires a positive id and ordinary input without LF",
      )
    }
  }
  if anchor.paragraph != focus.paragraph || text.contains("\n") {
    return Some(self.prepare_structural_range(selection, text))
  }
  let nodes = WordTree::new(self.document()).nodes
  let texts = self.editable_texts(anchor.paragraph)
  let content = texts.map(node => nodes[node.id].text).join("")
  let boundaries = @layout.grapheme_boundaries(content)
  validate_position(anchor, boundaries)
  validate_position(focus, boundaries)
  let start = anchor.offset.min(focus.offset)
  let end = anchor.offset.max(focus.offset)
  if content[start:end] == text {
    return None
  }
  if texts.is_empty() {
    return Some(self.prepare_empty(anchor.paragraph, text))
  }
  let affinity = if anchor.offset <= focus.offset {
    anchor.affinity
  } else {
    focus.affinity
  }
  let continuing = start == end &&
    self.selection == Some(selection) &&
    !text.is_empty()
  let insertion = for node in texts; offset = 0 {
    let length = nodes[node.id].text.length()
    if continuing &&
      self.typing_text == Some(node.id) &&
      start >= offset &&
      start <= offset + length {
      break node.id
    }
    if start < offset + length ||
      (start == offset + length && affinity == "before") {
      break node.id
    }
    continue offset + length
  } nobreak {
    texts.last().unwrap().id
  }
  let changes : Map[Int, String] = Map([])
  let mut offset = 0
  for node in texts {
    let before = nodes[node.id].text
    let length = before.length()
    let left = (start - offset).clamp(min=0, max=length)
    let right = (end - offset).clamp(min=0, max=length)
    let after = before[:left].to_owned() +
      (if node.id == insertion { text } else { "" }) +
      before[right:].to_owned()
    if before != after {
      changes[node.id] = after
    }
    offset += length
  }
  let updated = content[:start].to_owned() + text + content[end:].to_owned()
  let caret = @layout.grapheme_boundaries(updated)
    .iter()
    .filter(offset => offset >= start + text.length())
    .next()
    .unwrap()
  let position = {
    ..anchor,
    offset: caret,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let after : Selection = { anchor: position, focus: position, }
  let prepared = self.prepare_text(changes, Some(after), anchor.paragraph)
  Some({
    ..prepared,
    typing_text: if text.is_empty() {
      None
    } else {
      Some(insertion)
    },
    join_group: continuing,
  })
}

///|
fn edit_bytes(edit : @xml.Edit) -> Int raise @failure.Failure {
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Single edit exceeds history byte budget")
  }
  bytes.to_int()
}

///|
fn Session::commit_text(
  self : Session,
  changes : Map[Int, String],
  after : Selection?,
  paragraph : Int,
  input_group~ : Int? = None,
  join_group~ : Bool = false,
) -> Unit raise @failure.Failure {
  let prepared = self.prepare_text(changes, after, paragraph)
  self.commit_edit(prepared.edit, prepared.document, input_group~, join_group~)
}

///|
fn Session::prepare_text(
  self : Session,
  changes : Map[Int, String],
  after : Selection?,
  paragraph : Int,
) -> PreparedEdit raise @failure.Failure {
  let (candidate, xml) = self.document().edit_text(changes)
  {
    edit: {
      xml: [xml],
      before: self.selection,
      after,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  }
}

///|
fn Session::commit_edit(
  self : Session,
  edit : Edit,
  candidate : @xml.Document,
  input_group~ : Int? = None,
  join_group~ : Bool = false,
) -> Unit raise @failure.Failure {
  let previous = if join_group &&
    input_group is Some(_) &&
    self.input_group == input_group &&
    self.redo.is_empty() {
    self.history
    .last()
    .filter(old => {
      old.after == edit.before && old.bytes <= history_byte_limit - edit.bytes
    })
  } else {
    None
  }
  self.accept_document(candidate, edit.after)
  for old in self.redo {
    self.history_bytes -= old.bytes
  }
  self.redo.clear()
  let edit = if previous is Some(old) {
    ignore(self.history.pop())
    self.history_bytes -= old.bytes
    old.xml.append(edit.xml)
    let paragraphs = old.paragraphs.copy()
    for paragraph in edit.paragraphs {
      if !paragraphs.contains(paragraph) {
        paragraphs.push(paragraph)
      }
    }
    {
      ..edit,
      xml: old.xml,
      before: old.before,
      paragraphs,
      bytes: old.bytes + edit.bytes,
    }
  } else {
    edit
  }
  while self.history.length() >= history_entry_limit ||
        self.history_bytes > history_byte_limit - edit.bytes {
    self.history_bytes -= self.history.remove(0).bytes
  }
  self.history.push(edit)
  self.history_bytes += edit.bytes
  self.input_group = input_group
}

///|
fn Session::apply_edit(
  self : Session,
  edit : Edit,
  forward~ : Bool,
) -> Unit raise @failure.Failure {
  let mut candidate = self.document()
  // shortcut: Replay reparses XML per step; compact patches during P4 latency work.
  for index in 0..<edit.xml.length() {
    let step = if forward { index } else { edit.xml.length() - 1 - index }
    candidate = candidate.apply(edit.xml[step], forward~)
  }
  self.accept_document(
    candidate,
    if forward {
      edit.after
    } else {
      edit.before
    },
  )
}

///|
fn Session::accept_document(
  self : Session,
  candidate : @xml.Document,
  selection : Selection?,
) -> Unit raise @failure.Failure {
  guard self.revision < 0x7fffffff else {
    @failure.reject("limit-exceeded", "Revision exhausted")
  }
  let bytes = candidate.bytes()
  self.opc.validate_replacements(Map::from_array([(self.main, bytes)]))
  let texts = docx_texts(WordTree::new(candidate))
  self.document = Some(candidate)
  self.texts = texts
  self.selection = selection
  self.typing_text = None
  self.input_group = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.revision += 1
}

///|
pub fn Session::undo_edit(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.history.last() is Some(edit) else {
    self.input_group = None
    return self.edit_state()
  }
  self.apply_edit(edit, forward=false)
  ignore(self.history.pop())
  self.redo.push(edit)
  self.edit_result(edit.paragraphs)
}

///|
pub fn Session::redo_edit(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.redo.last() is Some(edit) else {
    self.input_group = None
    return self.edit_state()
  }
  self.apply_edit(edit, forward=true)
  ignore(self.redo.pop())
  self.history.push(edit)
  self.edit_result(edit.paragraphs)
}
