///|
priv struct ConvertRequest {
  revision : @common.RequestInt
  pages : PdfPages
  format : String
  acceptLoss : Bool
  budget : @common.RequestArchiveBudget
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct ConvertedPage {
  source : String
  target : Int32
} derive(ToJson)

///|
priv struct ConversionResponse {
  revision : Int32
  format : String
  status : String
  reason : String
  warnings : Array[String]
  pages : Array[ConvertedPage]
  bytes : Json
} derive(ToJson)

///|
let conversion_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "convertPdfOffice": (context, session, input) => {
    guard input is { "budget": _, .. } else {
      @failure.reject(
        "invalid-budget", "Explicit Office output budget is required",
      )
    }
    let command : ConvertRequest = @common.request(input)
    let result = @convert.convert(
      session,
      command.revision.value,
      command.pages.value,
      command.format,
      command.acceptLoss,
      command.budget.value,
      context.probe,
      command.profile.value,
      decoded=context.images,
    )
    let output : ConversionResponse = {
      revision: result.revision,
      format: result.format,
      status: result.status,
      reason: result.reason,
      warnings: result.warnings,
      pages: result.pages.map(page => {
        source: page.source,
        target: page.target,
      }),
      bytes: match result.bytes {
        Some(bytes) => Json(context.output.add(bytes))
        None => Json::null()
      },
    }
    ToJson::to_json(output).stringify()
  },
}
