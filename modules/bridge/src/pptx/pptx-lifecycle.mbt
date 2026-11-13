///|
#derive(@json.FromJson)
priv struct OpenRequest {
  budget : @common.RequestArchiveBudget
  dateTime : String?
}

///|
fn pptx_open_request(
  context : Context,
  input : Json,
) -> OpenRequest raise @failure.Failure {
  guard context.pptx is None && context.ranged is None else {
    @failure.reject("invalid-operation", "A document session is already open")
  }
  guard input is { "budget": _, .. } else {
    @failure.reject("invalid-budget", "Explicit budget is required")
  }
  @common.request(input)
}

///|
fn Context::accept_presentation(
  self : Context,
  session : @model.Session,
) -> Json raise @failure.Failure {
  errdefer session.close()
  let result = session.query()
  self.pptx = Some(session)
  result
}

///|
let lifecycle_handlers : Map[
  String,
  (Context, Json) -> Json raise @failure.Failure,
] = {
  "inputLimits": (_context, _input) => {
    let limits : PptxInputLimits = {
      fontBytes: @layout.FontInputBytes,
      exportBytes: @layout.ExportBytes,
      textFragmentUnits: @model.TextFragmentUnits,
      objectFragmentUnits: @model.ObjectFragmentUnits,
      importBytes: @model.SlideImportBytes,
      imageBytes: @model.ImageInputBytes,
      mediaBytes: @model.MediaInputBytes,
      rgbaBytes: @layout.ImageBytes,
      showInkBatchPoints: @model.ShowInkBatchPoints,
    }
    ToJson::to_json(limits)
  },
  "budget": (_context, _input) => archive_budget(),
  "fileBudgetPptx": (_context, _input) => {
    archive_budget(budget={
      ..@archive.Budget::default(),
      file_bytes: 256 * 1024 * 1024,
      entry_bytes: 64 * 1024 * 1024,
      total_bytes: 512 * 1024 * 1024,
      output_bytes: 256 * 1024 * 1024,
    })
  },
  "startPptxReader": (context, input) => context.start_reader(input),
  "openPptxReader": (context, _input) => context.open_reader(),
  "cancelPptxRange": (context, _input) => {
    if context.ranged is Some(ranged) {
      if context.pptx is None {
        ranged.close()
        context.ranged = None
      } else {
        ranged.cancel()
      }
    }
    Json::null()
  },
  "supplyPptxRange": (context, input) => {
    guard context.ranged is Some(ranged) else {
      @failure.reject("invalid-operation", "PPTX source reader is unavailable")
    }
    let command : @common.BytesRequest = @common.request(input)
    ranged.ranges.supply(command.bytes)
    Json::null()
  },
  "rasterHeaderPptx": (_context, input) => {
    @common.office_upload_header(
      input,
      @model.ImageInputBytes,
      @model.verifies_upload_raster,
    )
  },
  "createPptx": (context, input) => {
    let command = pptx_open_request(context, input)
    let budget : @archive.Budget = command.budget.value
    let session = match command.dateTime {
      Some(date_time) => @model.Session::create(budget, date_time~)
      None => @model.Session::create(budget)
    }
    context.accept_presentation(session)
  },
  "openPptx": (context, input) => {
    let command = pptx_open_request(context, input)
    let budget = command.budget.value
    let source : @common.BytesRequest = @common.request(input)
    let bytes = @common.byte_input(
      source.bytes,
      budget.file_bytes.min(budget.retained_bytes),
    )
    let session = match command.dateTime {
      Some(date_time) => @model.Session::open(bytes, budget, date_time~)
      None => @model.Session::open(bytes, budget)
    }
    context.accept_presentation(session)
  },
}
