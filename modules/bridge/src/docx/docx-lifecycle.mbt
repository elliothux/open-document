///|
priv struct OpenRequest {
  budget : @common.RequestArchiveBudget
  bytes : String
  password : String?
} derive(@json.FromJson)

///|
priv struct ShapeRequest {
  size : Json
  text : String
  language : String
} derive(@json.FromJson)

///|
fn Context::require_unopened(
  self : Context,
  input : Json,
) -> Json raise @failure.Failure {
  guard self.docx is None else {
    @failure.reject("invalid-operation", "DOCX session is already open")
  }
  guard input is { "budget": budget, .. } else {
    @failure.reject("invalid-budget", "Explicit budget is required")
  }
  budget
}

///|
fn Context::accept_docx(
  self : Context,
  session : @model.Session,
) -> Json raise @failure.Failure {
  errdefer session.close()
  let result = session.query()
  self.docx = Some(session)
  result
}

///|
let lifecycle_handlers : Map[
  String,
  (Context, Json) -> Json raise @failure.Failure,
] = {
  "budget": (_context, _input) => archive_budget(),
  "rasterHeaderDocx": (_context, input) => {
    @common.office_upload_header(
      input,
      @model.ImageInputBytes,
      @model.verifies_upload_raster,
    )
  },
  "inputLimits": (_context, _input) => {
    let limits : DocxInputLimits = {
      fontBytes: @layout.FontInputBytes,
      exportBytes: @layout.ExportBytes,
      imageBytes: @model.ImageInputBytes,
      rgbaBytes: @layout.ImageBytes,
      inkPoints: @model.InkStrokePoints,
      markupSourceUnits: @model.MarkupSourceUnits,
      clipboardFragmentUnits: @model.ClipboardFragmentUnits,
      textCommandUnits: @model.TextCommandUnits,
      revisionEntries: @model.RevisionEntries,
    }
    ToJson::to_json(limits)
  },
  "shape": (context, input) => {
    let command : ShapeRequest = @common.request(input)
    guard command.size is Number(size, ..) else {
      @failure.reject("invalid-operation", "Invalid font size")
    }
    context.probe.shape(command.text, size, command.language).to_json()
  },
  "createDocx": (context, input) => {
    let budget : @common.RequestArchiveBudget = @common.request(
      context.require_unopened(input),
    )
    context.accept_docx(@model.Session::create(budget.value))
  },
  "openDocx": (context, input) => {
    ignore(context.require_unopened(input))
    let command : OpenRequest = @common.request(input)
    let budget : @archive.Budget = command.budget.value
    context.accept_docx(
      @model.Session::open(
        @common.byte_input(
          command.bytes,
          budget.file_bytes.min(budget.retained_bytes),
        ),
        budget,
        password?=command.password,
      ),
    )
  },
}
