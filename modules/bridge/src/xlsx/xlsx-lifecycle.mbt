///|
priv struct OpenRequest {
  budget : @common.RequestArchiveBudget
  randomSeed : String
  date : String?
} derive(@json.FromJson)

///|
priv struct DelimitedOptionsRequest {
  numbers : Bool
  dates : Bool
  formulas : Bool
} derive(@json.FromJson)

///|
priv struct ImportRequest {
  budget : @common.RequestArchiveBudget
  randomSeed : String
  date : String?
  delimiter : String
  options : DelimitedOptionsRequest
} derive(@json.FromJson)

///|
fn xlsx_open_request(
  context : Context,
  input : Json,
) -> Unit raise @failure.Failure {
  guard context.xlsx is None else {
    @failure.reject("invalid-operation", "A document session is already open")
  }
  guard input is { "budget": _, .. } else {
    @failure.reject("invalid-budget", "Explicit budget is required")
  }
}

///|
fn Context::accept_xlsx(
  self : Context,
  candidate : @model.Session,
) -> Json raise @failure.Failure {
  errdefer candidate.close()
  let result = candidate.query()
  self.xlsx = Some(candidate)
  result
}

///|
let lifecycle_handlers : Map[
  String,
  (Context, Json) -> Json raise @failure.Failure,
] = {
  "inputLimits": (_context, _input) => {
    let limits : XlsxInputLimits = {
      fontBytes: @layout.FontInputBytes,
      exportBytes: @layout.ExportBytes,
      drawingFragmentUnits: @model.DrawingFragmentUnits,
      imageBytes: @model.ImageInputBytes,
      rgbaBytes: @layout.ImageBytes,
      delimitedBytes: @model.DelimitedInputBytes,
    }
    ToJson::to_json(limits)
  },
  "budget": (_context, _input) => archive_budget(),
  "createXlsx": (context, input) => {
    xlsx_open_request(context, input)
    let command : OpenRequest = @common.request(input)
    let seed = @common.byte_input(command.randomSeed, 32)
    context.accept_xlsx(
      @model.Session::create(
        command.budget.value,
        date=command.date,
        random_seed=Some(seed),
      ),
    )
  },
  "openXlsx": (context, input) => {
    xlsx_open_request(context, input)
    let command : OpenRequest = @common.request(input)
    let budget : @archive.Budget = command.budget.value
    let seed = @common.byte_input(command.randomSeed, 32)
    let source : @common.BytesRequest = @common.request(input)
    context.accept_xlsx(
      @model.Session::open(
        @common.byte_input(
          source.bytes,
          budget.file_bytes.min(budget.retained_bytes),
        ),
        budget,
        date=command.date,
        random_seed=Some(seed),
      ),
    )
  },
  "importXlsxDelimited": (context, input) => {
    xlsx_open_request(context, input)
    let command : ImportRequest = @common.request(input)
    let budget : @archive.Budget = command.budget.value
    let seed = @common.byte_input(command.randomSeed, 32)
    let source : @common.BytesRequest = @common.request(input)
    context.accept_xlsx(
      @model.Session::import_delimited(
        @common.byte_input(
          source.bytes,
          budget.file_bytes
          .min(budget.retained_bytes)
          .min(@model.DelimitedInputBytes),
        ),
        command.delimiter,
        budget,
        numbers=command.options.numbers,
        dates=command.options.dates,
        formulas=command.options.formulas,
        date=command.date,
        random_seed=Some(seed),
      ),
    )
  },
}
