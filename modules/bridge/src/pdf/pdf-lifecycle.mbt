///|
priv struct BudgetRequest {
  fileBytes : @common.RequestInt
  objects : @common.RequestInt
  objectNumber : @common.RequestInt
  pages : @common.RequestInt
  revisions : @common.RequestInt
  depth : @common.RequestInt
  streamBytes : @common.RequestInt
  decodedBytes : @common.RequestInt
  steps : @common.RequestInt
  outputBytes : @common.RequestInt
} derive(@json.FromJson)

///|
fn BudgetRequest::budget(self : BudgetRequest) -> @model.PdfBudget {
  {
    fileBytes: self.fileBytes.value,
    objects: self.objects.value,
    objectNumber: self.objectNumber.value,
    pages: self.pages.value,
    revisions: self.revisions.value,
    depth: self.depth.value,
    streamBytes: self.streamBytes.value,
    decodedBytes: self.decodedBytes.value,
    steps: self.steps.value,
    outputBytes: self.outputBytes.value,
  }
}

///|
priv struct OpenPdfRequest {
  bytes : String
  budget : BudgetRequest
  password : String?
} derive(@json.FromJson)

///|
priv struct CreatePdfRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
  budget : BudgetRequest
} derive(@json.FromJson)

///|
priv struct RasterHeaderRequest {
  bytes : String
  offset : @common.RequestNumber
  total : @common.RequestNumber
  decode : Bool?
} derive(@json.FromJson)

///|
fn Context::replace_pdf(
  self : Context,
  candidate : @model.PdfSession,
) -> String raise @failure.Failure {
  errdefer candidate.close()
  let result = candidate.query()
  if self.pdf is Some(previous) {
    previous.close()
  }
  self.images.clear()
  self.pdf = Some(candidate)
  result.stringify()
}

///|
let lifecycle_handlers : Map[
  String,
  (Context, Json) -> String raise @failure.Failure,
] = {
  "inputLimits": (_context, _input) => {
    let limits : PdfInputLimits = {
      fontBytes: @layout.FontInputBytes,
      exportBytes: @layout.ExportBytes,
      rgbaBytes: @layout.ImageBytes,
      importBytes: @model.PdfBudget::default().fileBytes,
      inkStrokeCount: @model.InkStrokeCount,
      inkCoordinates: @model.AnnotationCoordinates,
      textUnits: @model.TextUnits,
    }
    ToJson::to_json(limits).stringify()
  },
  "defaultPdfBudget": (_context, _input) => {
    @model.PdfBudget::default().to_json().stringify()
  },
  "defaultPdfOfficeBudget": (_context, _input) => {
    @common.archive_budget().stringify()
  },
  "rasterHeaderPdf": (context, input) => {
    let command : RasterHeaderRequest = @common.request(input)
    let offset = command.offset.value
    let total = command.total.value
    let bytes = @common.byte_input(command.bytes, @layout.ImageBytes)
    let remaining = total - offset
    guard total <= 9007199254740991.0 &&
      offset >= 0 &&
      offset == offset.trunc() &&
      total == total.trunc() &&
      bytes.length().to_double() >= remaining.min(33) &&
      bytes.length().to_double() <= remaining else {
      @failure.reject("invalid-operation", "Invalid raster header window")
    }
    let header = @common.image_header_window(
      bytes,
      offset.to_int64(),
      total.to_int64(),
    )
    if command.decode == Some(true) &&
      offset == 0 &&
      total == bytes.length().to_double() &&
      header is @common.ImageDimensions(width, height, ..) &&
      @model.decode_upload_raster(bytes) is Some((w, h, rgba)) &&
      width == w &&
      height == h {
      let prepared : PdfRasterOutput = {
        width: w,
        height: h,
        bytes: context.output.add(rgba),
      }
      return ToJson::to_json(prepared).stringify()
    }
    header.to_json().stringify()
  },
  "openPdf": (context, input) => {
    guard input is { "budget": _, .. } else {
      @failure.reject("invalid-budget", "Explicit PDF budget is required")
    }
    if input is { "password": Null, .. } {
      @failure.reject("invalid-operation", "PDF password must be a string")
    }
    let command : OpenPdfRequest = @common.request(input)
    let budget = command.budget.budget()
    let candidate = @model.PdfSession::open(
      @common.byte_input(command.bytes, budget.fileBytes),
      budget,
      password=command.password,
    )
    context.replace_pdf(candidate)
  },
  "createPdf": (context, input) => {
    guard input is { "budget": _, .. } else {
      @failure.reject("invalid-budget", "Explicit PDF budget is required")
    }
    let command : CreatePdfRequest = @common.request(input)
    let candidate = @model.PdfSession::create(
      command.width.value,
      command.height.value,
      command.budget.budget(),
    )
    context.replace_pdf(candidate)
  },
}
