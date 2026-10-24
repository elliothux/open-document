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
  parts : Map[String, Array[@xml.Edit]]
  created : Map[String, @xml.Document]
  created_media : Map[String, Bytes]
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
  notes~ : Bool = false,
) -> Array[TextNode] raise @failure.Failure {
  let tree = WordTree::new(self.document())
  tree.check_editable_paragraph(
    paragraph,
    part=self.main,
    pictures=true,
    fields=true,
    math=true,
    notes~,
  )
  self.check_native_drawings(tree, paragraph)
  self.texts.filter(node => node.paragraph == paragraph)
}

///|
fn validate_position(
  position : Position,
  boundaries : Array[Int],
) -> Unit raise @failure.Failure {
  if position.frameStart is Some(start) &&
    (start <= position.offset || boundaries.binary_search(start) is Err(_)) {
    @failure.reject("invalid-position", "Invalid preferred frame boundary")
  }
  if position.bidiLevel is Some(level) && (level < 0 || level > 126) {
    @failure.reject("invalid-position", "Invalid cursor direction level")
  }
  guard (position.affinity == "before" || position.affinity == "after") &&
    boundaries.binary_search(position.offset) is Ok(_) else {
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
  let current = match (self.composition, self.drawing_gesture) {
    (Some({ prepared: Some(prepared), .. }), _)
    | (_, Some({ prepared: Some(prepared), .. })) => prepared.edit.after
    _ => self.selection
  }
  let selection : Json = match current {
    None => Json::null()
    Some(selection) => selection.to_json()
  }
  {
    "revision": self.revision,
    "defaultTabStop": self.default_tab(),
    "formatting": if self.composition is None &&
      self.drawing_gesture is None &&
      self.selection is Some(selection) {
      self.query_formatting(self.revision, selection)
    } else {
      Json::null()
    },
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
    "drawingGestureId": self.drawing_gesture
    .map(gesture => Json(gesture.id))
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
  let tree = WordTree::new(self.display_document())
  guard tree.text_box_drawing(selection.anchor.paragraph) ==
    tree.text_box_drawing(selection.focus.paragraph) else {
    @failure.reject("protected-content", "Selection crosses text box stories")
  }
  self.selection = Some(selection)
  self.input_group = None
  self.typing_text = None
  self.typing_format = None
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
  check_graphemes~ : Bool = true,
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  if tree.nodes.contains(position.paragraph) &&
    tree.nodes[position.paragraph].name == "p" &&
    tree
    .descendants(position.paragraph)
    .any(id => note_reference(tree.nodes[id])) {
    // A retained caret does not grant range mutation access to note references.
    self.check_note_paragraph(document, position.paragraph)
  } else {
    tree.check_editable_paragraph(
      position.paragraph,
      part=self.main,
      pictures=true,
      fields=true,
      math=true,
    )
  }
  self.check_native_drawings(tree, position.paragraph)
  let nodes = tree.nodes
  let texts = docx_texts(tree).filter(node => {
    node.paragraph == position.paragraph
  })
  let text = texts.map(node => inline_text(nodes[node.id])).join("")
  validate_position(position, editing_boundaries(text, check_graphemes))
}

///|
fn editing_boundaries(text : String, graphemes : Bool) -> Array[Int] {
  if graphemes {
    return @layout.grapheme_boundaries(text)
  }
  let result : Array[Int] = []
  for offset, _ in text.iter2() {
    result.push(offset)
  }
  result.push(text.length())
  result
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
    if prepared.edit.bytes == 0 {
      return self.select(revision, prepared.edit.after.unwrap())
    }
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
  check_graphemes~ : Bool = true,
) -> PreparedEdit? raise @failure.Failure {
  let prepared = self.prepare_plain_range(
    selection,
    text,
    input_group~,
    check_graphemes~,
    notes=true,
  )
  if self.typing_format is Some(patch) &&
    self.selection == Some(selection) &&
    selection.anchor.paragraph == selection.focus.paragraph &&
    selection.anchor.offset == selection.focus.offset &&
    !text.is_empty() &&
    prepared is Some(prepared) {
    return Some(self.prepare_formatted_input(selection, prepared, patch))
  }
  prepared
}

///|
fn Session::prepare_plain_range(
  self : Session,
  selection : Selection,
  text : String,
  input_group~ : Int? = None,
  check_graphemes~ : Bool = true,
  notes~ : Bool = false,
) -> PreparedEdit? raise @failure.Failure {
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Command input exceeds UTF-16 budget")
  }
  guard valid_inline_input(text) else {
    @failure.reject(
      "invalid-operation", "Invalid paragraph text or inline control",
    )
  }
  let anchor = selection.anchor
  let focus = selection.focus
  if text.iter().any(ch => ['\u2028', '\u000b', '\u000c'].contains(ch)) {
    self.check_display_math_input(selection)
  }
  if has_region_break(text) {
    let tree = WordTree::new(self.document())
    tree.check_region_break_input(anchor.paragraph, text)
    tree.check_region_break_input(focus.paragraph, text)
  }
  if input_group is Some(group) {
    guard group > 0 &&
      !text.is_empty() &&
      !text.contains("\n") &&
      !text.contains("\u2028") &&
      !has_region_break(text) &&
      !text.contains("\t") else {
      @failure.reject(
        "invalid-operation", "Input group requires a positive id and ordinary input without LF",
      )
    }
  }
  if anchor.paragraph != focus.paragraph || text.contains("\n") {
    if anchor.paragraph != focus.paragraph {
      let tree = WordTree::new(self.document())
      if self.table_cell_range(
          tree,
          selection,
          pictures=true,
          fields=true,
          math=true,
          notes~,
        )
        is Some(cells) {
        return Some(
          self.prepare_table_contents(
            tree,
            cells,
            text,
            check_graphemes~,
            notes~,
          ),
        )
      }
    }
    return Some(
      self.prepare_structural_range(selection, text, check_graphemes~, notes~),
    )
  }
  let tree = WordTree::new(self.document())
  let nodes = tree.nodes
  let texts = self.editable_texts(anchor.paragraph, notes~)
  if notes && texts.any(item => note_reference(nodes[item.id])) {
    ignore(
      self.paragraph_range(
        tree,
        selection,
        structural=false,
        fields=true,
        math=true,
        notes=true,
      ),
    )
  }
  let content = texts.map(node => inline_text(nodes[node.id])).join("")
  let boundaries = editing_boundaries(content, check_graphemes)
  validate_position(anchor, boundaries)
  validate_position(focus, boundaries)
  let start = anchor.offset.min(focus.offset)
  let end = anchor.offset.max(focus.offset)
  if content[start:end] == text &&
    !tree.has_drawing_range(texts, start, end, fields=true) {
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
    let length = inline_text(nodes[node.id]).length()
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
  let object_offsets : Map[Int, Int] = Map([])
  let mut offset = 0
  for node in texts {
    let before = inline_text(nodes[node.id])
    let length = before.length()
    let left = (start - offset).clamp(min=0, max=length)
    let right = (end - offset).clamp(min=0, max=length)
    let after = before[:left].to_owned() +
      (if node.id == insertion { text } else { "" }) +
      before[right:].to_owned()
    let picture = note_reference(nodes[node.id]) ||
      ["drawing", "fldSimple", "oMath", "oMathPara"].contains(
        nodes[node.id].name,
      )
    if picture && left == right {
      object_offsets[node.id] = if left == 0 && node.id == insertion {
        text.length()
      } else {
        0
      }
    }
    if before != after || (picture && left != right) {
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
  let prepared = self.prepare_text(
    changes,
    Some(after),
    anchor.paragraph,
    source=tree.index_range_changes({ ..anchor, offset: start, }, {
      ..focus,
      offset: end,
    }),
    object_offsets~,
    notes~,
  )
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
  source~ : Array[@xml.SourceChange] = [],
  object_offsets~ : Map[Int, Int] = Map([]),
  notes~ : Bool = false,
) -> PreparedEdit raise @failure.Failure {
  let (candidate, xml) = self.edit_inline_text(
    self.document(),
    changes,
    source~,
    object_offsets~,
    notes~,
  )
  {
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
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
  parts~ : Map[String, @xml.Document] = self.parts,
  media~ : Map[String, Bytes] = self.media,
  bookmark_edit~ : Bool = false,
  comment_edit~ : Bool = false,
  protection_edit~ : Bool = false,
) -> Unit raise @failure.Failure {
  if !protection_edit {
    self.check_document_protection()
  }
  let (parts, note_edits, note_bytes) = self.note_transition(candidate, parts)
  guard note_bytes <= history_byte_limit - edit.bytes else {
    @failure.reject("limit-exceeded", "Note input exceeds history budget")
  }
  let combined = edit.parts.copy()
  for part, steps in note_edits {
    combined.get_or_init(part, () => []).append(steps)
  }
  let edit = { ..edit, parts: combined, bytes: edit.bytes + note_bytes, }
  if !bookmark_edit {
    check_bookmark_integrity(self.document(), candidate)
  }
  if !comment_edit {
    check_comment_integrity(self.document(), candidate)
  }
  let previous = if join_group &&
    edit.parts.is_empty() &&
    edit.created.is_empty() &&
    edit.created_media.is_empty() &&
    input_group is Some(_) &&
    self.input_group == input_group &&
    self.redo.is_empty() {
    self.history
    .last()
    .filter(old => {
      old.parts.is_empty() &&
      old.created.is_empty() &&
      old.created_media.is_empty() &&
      old.after == edit.before &&
      old.bytes <= history_byte_limit - edit.bytes
    })
  } else {
    None
  }
  self.accept_document(candidate, edit.after, parts~, media~)
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
  let original_parts = self.parts
  let mut candidate = self.document()
  // shortcut: Replay reparses XML per step; compact patches during P4 latency work.
  for index in 0..<edit.xml.length() {
    let step = if forward { index } else { edit.xml.length() - 1 - index }
    candidate = candidate.apply(edit.xml[step], forward~)
  }
  let parts = self.parts.copy()
  for name, steps in edit.parts {
    let mut document = self.part_xml(name)
    for index in 0..<steps.length() {
      let step = if forward { index } else { steps.length() - 1 - index }
      document = document.apply(steps[step], forward~)
    }
    parts[name] = document
  }
  for name, document in edit.created {
    guard !self.opc.names.contains(name.to_lower()) else {
      @failure.reject(
        "invalid-operation", "History cannot replace an original part",
      )
    }
    if forward {
      guard !parts.contains(name) else {
        @failure.reject(
          "invalid-operation", "Created history part already exists",
        )
      }
      parts[name] = document
    } else {
      guard parts.get(name) is Some(current) &&
        current.source() == document.source() else {
        @failure.reject("invalid-operation", "Created history part has changed")
      }
      parts.remove(name)
    }
  }
  let media = self.media.copy()
  for name, bytes in edit.created_media {
    if forward {
      guard !media.contains(name) && !self.opc.names.contains(name.to_lower()) else {
        @failure.reject("invalid-operation", "Created image already exists")
      }
      media[name] = bytes
    } else {
      guard media.get(name) == Some(bytes) else {
        @failure.reject("invalid-operation", "Created image has changed")
      }
      media.remove(name)
    }
  }
  self.accept_document(
    candidate,
    if forward {
      edit.after
    } else {
      edit.before
    },
    parts~,
    media~,
  )
  if !forward {
    // Retain identity allocation after later edits were undone, for their next redo.
    for name, _ in edit.created {
      edit.created[name] = original_parts[name]
    }
  }
}

///|
fn Session::accept_document(
  self : Session,
  candidate : @xml.Document,
  selection : Selection?,
  parts~ : Map[String, @xml.Document] = self.parts,
  media~ : Map[String, Bytes] = self.media,
) -> Unit raise @failure.Failure {
  guard self.revision < 0x7fffffff else {
    @failure.reject("limit-exceeded", "Revision exhausted")
  }
  self.opc.validate_changes(self.replacements(candidate, parts, media~))
  if candidate
    .nodes()
    .any(node => node.uri == word_shape_uri && node.name == "txbx") {
    ignore(
      { ..self, document: Some(candidate), parts, media, }.flow_from(candidate),
    )
  }
  ignore({ ..self, document: Some(candidate), parts, media, }.default_tab())
  let texts = docx_texts(WordTree::new(candidate))
  self.document = Some(candidate)
  self.parts = parts
  self.media = media
  self.texts = texts
  self.selection = selection
  self.typing_text = None
  self.typing_format = None
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
