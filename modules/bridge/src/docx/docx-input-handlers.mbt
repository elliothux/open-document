///|
priv struct DirectionRequest {
  revision : @common.RequestInt
  direction : String
} derive(@json.FromJson)

///|
priv struct TabRequest {
  revision : @common.RequestInt
  backward : Bool
} derive(@json.FromJson)

///|
priv struct CompositionRequest {
  revision : @common.RequestInt
  compositionId : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct CompositionTextRequest {
  revision : @common.RequestInt
  compositionId : @common.RequestInt
  text : String
} derive(@json.FromJson)

///|
priv struct ReplaceRangeRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  text : String
  inputGroup : @common.RequestInt?
} derive(@json.FromJson)

///|
priv struct ReplaceNodeRequest {
  revision : @common.RequestInt
  node : @common.RequestInt
  text : String
} derive(@json.FromJson)

///|
fn Context::clear_edit_layout(
  self : Context,
  result : Json,
  previous? : Int32,
) -> Json raise @failure.Failure {
  let retain = previous is Some(revision) &&
    self.docx is Some(session) &&
    session.current_revision() == revision
  if !retain {
    self.layout = None
  }
  result
}

///|
let input_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "selectDocx": (_context, session, input) => {
    let command : RevisionSelectionRequest = @common.request(input)
    session.select(command.revision.value, command.selection.selection())
  },
  "selectAllDocx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.select_all(revision)
  },
  "queryFormatting": (context, session, input) => {
    let command : RevisionSelectionRequest = @common.request(input)
    session.query_formatting(
      command.revision.value,
      command.selection.selection(),
      layout?=context.layout,
    )
  },
  "query": (_context, session, _input) => session.query(),
  "editState": (_context, session, _input) => session.edit_state(),
  "docxOverview": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.overview(revision)
  },
  "docxComments": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.comments(revision)
  },
  "navigateComment": (_context, session, input) => {
    let command : DirectionRequest = @common.request(input)
    session.navigate_comment(command.revision.value, command.direction)
  },
  "enterDocx": (context, session, input) => {
    let revision = @common.request_revision(input)
    context.clear_edit_layout(session.enter(revision))
  },
  "tabDocx": (context, session, input) => {
    let command : TabRequest = @common.request(input)
    let previous = command.revision.value
    context.clear_edit_layout(
      session.tab(previous, command.backward),
      previous~,
    )
  },
  "beginComposition": (context, session, input) => {
    let revision = @common.request_revision(input)
    context.clear_edit_layout(session.begin_composition(revision))
  },
  "updateComposition": (context, session, input) => {
    let command : CompositionTextRequest = @common.request(input)
    context.clear_edit_layout(
      session.update_composition(
        command.revision.value,
        command.compositionId.value,
        command.text,
      ),
    )
  },
  "commitComposition": (context, session, input) => {
    let command : CompositionTextRequest = @common.request(input)
    context.clear_edit_layout(
      session.commit_composition(
        command.revision.value,
        command.compositionId.value,
        command.text,
      ),
    )
  },
  "cancelComposition": (context, session, input) => {
    let command : CompositionRequest = @common.request(input)
    context.clear_edit_layout(
      session.cancel_composition(
        command.revision.value,
        command.compositionId.value,
      ),
    )
  },
  "replaceRange": (context, session, input) => {
    let command : ReplaceRangeRequest = @common.request(input)
    let previous = command.revision.value
    let result = session.replace_range(
      previous,
      command.selection.selection(),
      command.text,
      input_group=command.inputGroup.map(value => value.value),
    )
    context.clear_edit_layout(result, previous~)
  },
  "deleteDocx": (context, session, input) => {
    let command : DirectionRequest = @common.request(input)
    let previous = command.revision.value
    context.clear_edit_layout(
      session.delete(previous, command.direction),
      previous~,
    )
  },
  "undoDocx": (context, session, input) => {
    let revision = @common.request_revision(input)
    let previous = revision
    context.clear_edit_layout(session.undo_edit(previous), previous~)
  },
  "redoDocx": (context, session, input) => {
    let revision = @common.request_revision(input)
    let previous = revision
    context.clear_edit_layout(session.redo_edit(previous), previous~)
  },
  "replaceNode": (context, session, input) => {
    let command : ReplaceNodeRequest = @common.request(input)
    let previous = command.revision.value
    let revision = session.replace(command.node.value, previous, command.text)
    context.clear_edit_layout({ "revision": revision }, previous~)
  },
  "saveDocx": (context, session, _input) => {
    "bytes": context.output.add(session.save()),
  },
}
