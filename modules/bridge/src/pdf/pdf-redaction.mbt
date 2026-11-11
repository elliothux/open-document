///|
priv struct RedactionRegionRequest {
  page : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
fn RedactionRegionRequest::region(
  self : RedactionRegionRequest,
) -> @model.PdfRedactionRegion {
  {
    page: self.page,
    x: self.x.value,
    y: self.y.value,
    width: self.width.value,
    height: self.height.value,
  }
}

///|
priv struct RedactionRequest {
  regions : Array[RedactionRegionRequest]
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
fn redaction_request(
  input : Json,
) -> (Int32, RedactionRequest) raise @failure.Failure {
  // Preserve revision-error precedence over the special selection error.
  let revision = @common.request_revision(input)
  guard input is { "regions": Array(regions), .. } &&
    !regions.is_empty() &&
    regions.length() <= @model.RedactionRegionCount else {
    @failure.reject(
      "invalid-selection", "Choose bounded PDF redaction rectangles",
    )
  }
  (revision, @common.request(input))
}

///|
let redaction_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "previewPdfRedaction": (context, session, input) => {
    let (revision, command) = redaction_request(input)
    let result = session.preview_redaction(
      revision,
      command.regions.map(region => region.region()),
      context.probe,
      command.profile.value,
      decoded=context.images,
    )
    ToJson::to_json(result).stringify()
  },
  "exportPdfRedaction": (context, session, input) => {
    let (revision, command) = redaction_request(input)
    let (bytes, warnings) = session.export_redaction(
      revision,
      command.regions.map(region => region.region()),
      context.probe,
      command.profile.value,
      decoded=context.images,
    )
    let output : PdfExportOutput = {
      revision,
      bytes: context.output.add(bytes),
      warnings,
    }
    ToJson::to_json(output).stringify()
  },
}
