///|
priv struct PdfSource {
  reader : @model.PdfRangeReader
  ranges : @common.RangeInput
}

///|
#derive(@json.FromJson)
priv struct PdfSourceRequest {
  size : @common.RequestInt
  budget : BudgetRequest
}

///|
fn Context::start_pdf_reader(
  self : Context,
  input : Json,
) -> String raise @failure.Failure {
  let command : PdfSourceRequest = @common.request(input)
  let ranges = @common.RangeInput::new()
  let reader = @model.PdfRangeReader::new(
    command.size.value,
    (offset, length) => ranges.read(offset, length),
    command.budget.budget(),
  )
  self.source_candidate = Some({ reader, ranges, })
  "null"
}

///|
fn Context::open_pdf_reader(self : Context) -> String raise @failure.Failure {
  guard self.source_candidate is Some(source) else {
    @failure.reject("invalid-operation", "PDF source reader is unavailable")
  }
  let session = source.reader.open_preview()
  let output = self.replace_pdf(session)
  source.ranges.clear()
  self.ranged = Some(source.ranges)
  self.source_candidate = None
  output
}

///|
fn Context::supply_pdf_range(
  self : Context,
  input : Json,
) -> String raise @failure.Failure {
  let ranges = if self.source_candidate is Some(candidate) {
    Some(candidate.ranges)
  } else {
    self.ranged
  }
  guard ranges is Some(ranges) else {
    @failure.reject("invalid-operation", "PDF source reader is unavailable")
  }
  let command : @common.BytesRequest = @common.request(input)
  ranges.supply(command.bytes)
  "null"
}

///|
fn Context::cancel_pdf_range(self : Context) -> String {
  if self.source_candidate is Some(candidate) {
    candidate.ranges.clear()
    self.source_candidate = None
  } else if self.ranged is Some(ranges) {
    ranges.clear()
    if self.pdf is Some(session) {
      session.cancel_preview_read()
    }
  }
  "null"
}

///|
fn Context::clear_pdf_ranges(self : Context) -> Unit {
  if self.ranged is Some(ranges) {
    ranges.clear()
  }
  self.ranged = None
}
