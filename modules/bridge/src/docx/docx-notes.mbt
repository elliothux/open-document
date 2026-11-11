///|
#derive(@json.FromJson)
priv struct NoteNumberingRequest {
  revision : @common.RequestInt
  kind : String
  section : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct NoteNumberingInput {
  format : String
  start : @common.RequestNumber
  restart : String
}

///|
#derive(@json.FromJson)
priv struct SetNoteNumberingRequest {
  revision : @common.RequestInt
  kind : String
  section : @common.RequestInt
  numbering : NoteNumberingInput
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct EndnotePositionRequest {
  revision : @common.RequestInt
  position : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct NoteEditRequest[T] {
  revision : @common.RequestInt
  note : T
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct NoteInsertInput {
  kind : String
  text : String
}

///|
#derive(@json.FromJson)
priv struct NoteRemoveInput {
  kind : String
  id : String
}

///|
#derive(@json.FromJson)
priv struct NoteEditInput {
  kind : String
  id : String
  text : String
}

///|
fn[T : @json.FromJson] note_edit_request(
  input : Json,
  field_count : Int32,
) -> NoteEditRequest[T] raise @failure.Failure {
  guard input is { "note": Object(fields), .. } &&
    fields.length() == field_count else {
    @failure.reject("invalid-operation", "Invalid native note fields")
  }
  @common.request(input)
}

///|
let note_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "docxNotes": (_context, session, input) => {
    session.notes(@common.request_revision(input))
  },
  "noteNumbering": (_context, session, input) => {
    let command : NoteNumberingRequest = @common.request(input)
    session.note_numbering(
      command.revision.value,
      command.kind,
      command.section.value,
    )
  },
  "setNoteNumbering": (self, session, input) => {
    guard input is { "numbering": Object(fields), .. } && fields.length() == 3 else {
      @failure.reject("invalid-operation", "Invalid note numbering fields")
    }
    let command : SetNoteNumberingRequest = @common.request(input)
    let start = command.numbering.start.value
    guard start >= 0 &&
      start <= @layout.NumberingStartMax.to_double() &&
      start.floor() == start else {
      @failure.reject("invalid-operation", "Invalid note numbering start")
    }
    let revision = command.revision.value
    let result = session.set_note_numbering(
      revision,
      command.kind,
      command.section.value,
      @layout.PageNumbering::new(
        start=start.to_int64(),
        format=command.numbering.format,
      ),
      command.numbering.restart,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setEndnotePosition": (self, session, input) => {
    let command : EndnotePositionRequest = @common.request(input)
    let revision = command.revision.value
    let result = session.set_endnote_position(
      revision,
      command.position,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "insertDocxNote": (self, session, input) => {
    let command : NoteEditRequest[NoteInsertInput] = note_edit_request(input, 2)
    let revision = command.revision.value
    let result = session.insert_note(
      revision,
      command.note.kind,
      command.note.text,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "removeDocxNote": (self, session, input) => {
    let command : NoteEditRequest[NoteRemoveInput] = note_edit_request(input, 2)
    let revision = command.revision.value
    let result = session.remove_note(
      revision,
      command.note.kind,
      command.note.id,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxNote": (self, session, input) => {
    let command : NoteEditRequest[NoteEditInput] = note_edit_request(input, 3)
    let revision = command.revision.value
    let result = session.edit_note(
      revision,
      command.note.kind,
      command.note.id,
      command.note.text,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
}
