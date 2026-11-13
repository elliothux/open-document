///|
#derive(@json.FromJson)
priv struct ViewRequest {
  layoutId : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct PageReadRequest {
  revision : @common.RequestInt
  page : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SearchRequest {
  revision : @common.RequestInt
  page : String
  query : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct RangeRequest {
  revision : @common.RequestInt
  anchorPage : String
  anchor : @common.RequestInt
  focusPage : String
  focus : @common.RequestInt
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct RevisionProfileRequest {
  revision : @common.RequestInt
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct HitRequest {
  layoutId : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct SelectionRequest {
  layoutId : @common.RequestInt
  anchor : @common.RequestInt
  focus : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct NoteRequest {
  revision : @common.RequestInt
  page : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  text : String
}

///|
#derive(@json.FromJson)
priv struct HighlightRequest {
  revision : @common.RequestInt
  layoutId : @common.RequestInt
}

///|
let reading_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "queryPdf": (_context, session, _input) => session.query().stringify(),
  "pdfNavigation": (_context, session, input) => {
    let page = match input {
      { "page": String(page), .. } => Some(page)
      { "page": _, .. } =>
        @failure.reject("invalid-operation", "Invalid PDF navigation page")
      _ => None
    }
    ToJson::to_json(session.navigation(page~)).stringify()
  },
  "pdfMetadata": (_context, session, _input) => {
    ToJson::to_json(session.metadata()).stringify()
  },
  "extractPdfText": (context, session, input) => {
    let command : PageReadRequest = @common.request(input)
    let result = session.extract(
      command.revision.value,
      command.page,
      context.probe,
      command.profile.value,
    )
    ToJson::to_json(result).stringify()
  },
  "searchPdfPage": (context, session, input) => {
    let command : SearchRequest = @common.request(input)
    let result = session.search(
      command.revision.value,
      command.page,
      command.query,
      context.probe,
      command.profile.value,
    )
    ToJson::to_json(result).stringify()
  },
  "selectPdfRange": (context, session, input) => {
    let command : RangeRequest = @common.request(input)
    let result = session.select_range(
      command.revision.value,
      command.anchorPage,
      command.anchor.value,
      command.focusPage,
      command.focus.value,
      context.probe,
      command.profile.value,
    )
    ToJson::to_json(result).stringify()
  },
  "selectedPdfRange": (context, session, input) => {
    let command : RevisionProfileRequest = @common.request(input)
    let result = session.selected_range(
      command.revision.value,
      context.probe,
      command.profile.value,
    )
    ToJson::to_json(result).stringify()
  },
  "hitTestPdf": (_context, session, input) => {
    let command : HitRequest = @common.request(input)
    let result = session.hit(
      command.layoutId.value,
      command.x.value,
      command.y.value,
    )
    ToJson::to_json(result).stringify()
  },
  "selectPdf": (_context, session, input) => {
    let command : SelectionRequest = @common.request(input)
    let result = session.select_text(
      command.layoutId.value,
      command.anchor.value,
      command.focus.value,
    )
    ToJson::to_json(result).stringify()
  },
  "selectedPdfText": (_context, session, input) => {
    let command : ViewRequest = @common.request(input)
    let result : PdfSelectedTextOutput = {
      text: session.selected_text(command.layoutId.value),
    }
    ToJson::to_json(result).stringify()
  },
  "releasePdfView": (_context, session, input) => {
    let command : ViewRequest = @common.request(input)
    session.release_view(command.layoutId.value)
    session.query().stringify()
  },
  "savePdf": (context, session, input) => {
    let revision = @common.request_revision(input)
    let result : PdfBytesOutput = {
      revision,
      bytes: context.output.add(session.save(revision)),
    }
    ToJson::to_json(result).stringify()
  },
  "undoPdf": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo_edit(revision, false).stringify()
  },
  "redoPdf": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo_edit(revision, true).stringify()
  },
  "addPdfNote": (_context, session, input) => {
    let command : NoteRequest = @common.request(input)
    session
    .add_note(
      command.revision.value,
      command.page,
      command.x.value,
      command.y.value,
      command.text,
    )
    .stringify()
  },
  "highlightPdfText": (_context, session, input) => {
    let command : HighlightRequest = @common.request(input)
    session
    .add_highlight(command.revision.value, command.layoutId.value)
    .stringify()
  },
}
