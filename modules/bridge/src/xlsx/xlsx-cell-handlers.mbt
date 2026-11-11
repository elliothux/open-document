///|
let cell_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "queryXlsx": (_context, session, input) => {
    if input is { "sheet": Null, .. } || input is { "range": Null, .. } {
      @failure.reject(
        "invalid-operation", "Worksheet and range must be strings",
      )
    }
    let command : QueryRequest = @common.request(input)
    session.query(sheet=command.sheet, range=command.range)
  },
  "selectXlsx": (_context, session, input) => {
    let command : CellRangeRequest = @common.request(input)
    session.select(command.revision.value, command.sheet, command.range)
  },
  "replaceXlsx": (_context, session, input) => {
    let command : ReplaceCellsRequest = @common.request(input)
    session.replace(
      command.revision.value,
      command.sheet,
      command.range,
      xlsx_replacement_values(command.values),
      literal=command.literal,
      accept_warnings=command.acceptWarnings,
    )
  },
  "recalculateXlsx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.recalculate(revision)
  },
  "undoXlsx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo(revision)
  },
  "redoXlsx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo(revision, redo=true)
  },
  "saveXlsx": (context, session, _input) => {
    "bytes": context.output.add(session.save()),
  },
  "selectionXlsx": (_context, session, input) => {
    let command : LayoutRequest = @common.request(input)
    Json(session.selection_geometry(command.layoutId.value))
  },
  "fillPreviewXlsx": (_context, session, input) => {
    let command : FillPreviewRequest = @common.request(input)
    Json(
      session.fill_preview(
        command.layoutId.value,
        command.target.target,
        ctrl=command.target.ctrl,
      ),
    )
  },
  "viewportXlsx": (context, session, input) => {
    if input is { "screenScale": Null, .. } {
      @failure.reject("invalid-operation", "Screen scale must be numeric")
    }
    let command : ViewportRequest = @common.request(input)
    let viewport = session.viewport(
      command.sheet,
      command.scrollX.value,
      command.scrollY.value,
      command.width.value,
      command.height.value,
      context.probe,
      command.profile.value,
      reveal=command.reveal,
      images=context.images,
      slicer_hover=xlsx_slicer_hover(input),
      screen_scale=command.screenScale.map(value => value.value),
      chart_wire=true,
      compact_cells=command.compactCells.unwrap_or(false),
    )
    context.encode_chart_tiles(viewport, session.viewport_chart_tiles())
  },
  "hitXlsx": (_context, session, input) => {
    let command : HitRequest = @common.request(input)
    {
      "address": session.hit(
        command.layoutId.value,
        command.x.value,
        command.y.value,
      ),
    }
  },
  "navigateXlsx": (_context, session, input) => {
    let command : NavigateRequest = @common.request(input)
    session.navigate(
      command.revision.value,
      command.direction,
      command.extend_flag,
    )
  },
  "copyXlsx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    { "text": session.copy(revision) }
  },
  "captureXlsxCells": (_context, session, input) => {
    let revision = @common.request_revision(input)
    Json(session.capture_cells(revision))
  },
  "pasteXlsxCells": (_context, session, input) => {
    let command : PasteCellsRequest = @common.request(input)
    session.paste_cells(
      command.revision.value,
      xlsx_copied_cells(command.copied),
      command.mode,
      transpose=command.transpose,
      accept_warnings=command.acceptWarnings,
    )
  },
  "pasteXlsx": (_context, session, input) => {
    let command : PasteTextRequest = @common.request(input)
    session.paste(
      command.revision.value,
      command.text,
      accept_warnings=command.acceptWarnings,
    )
  },
  "clearXlsx": (_context, session, input) => {
    let command : ClearRequest = @common.request(input)
    session.clear(command.revision.value, mode=command.mode)
  },
  "exportXlsxCsv": (context, session, input) => {
    let command : ExportCsvRequest = @common.request(input)
    {
      "bytes": context.output.add(
        session.export_csv(command.revision.value, selection=command.selection),
      ),
    }
  },
  "findXlsx": (_context, session, input) => {
    let command : FindRequest = @common.request(input)
    session.find(
      command.revision.value,
      command.sheet,
      command.text,
      command.options.options(),
    )
  },
  "replaceXlsxMatches": (_context, session, input) => {
    let command : ReplaceMatchesRequest = @common.request(input)
    session.replace_matches(
      command.revision.value,
      command.sheet,
      command.text,
      command.options.options(),
      command.replacement,
      command.index.bind(value => value.value).map(value => value.value),
    )
  },
  "autoFitXlsx": (context, session, input) => {
    let command : AutoFitRequest = @common.request(input)
    guard command.axis == "rows" || command.axis == "columns" else {
      @failure.reject("invalid-operation", "Invalid automatic fitting axis")
    }
    session.auto_fit(
      command.revision.value,
      command.sheet,
      command.first.value,
      command.last.value,
      context.probe,
      command.profile.value,
      rows=command.axis == "rows",
    )
  },
  "captureXlsxFormat": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.capture_format(revision)
  },
  "applyXlsxFormat": (_context, session, input) => {
    let command : ApplyFormatRequest = @common.request(input)
    let (pattern, merges) = xlsx_copied_format(command.format)
    session.apply_format(command.revision.value, pattern, merges)
  },
  "formatXlsxCells": (_context, session, input) => {
    let command : FormatCellsRequest = @common.request(input)
    session.format_cells(command.revision.value, command.patch.value)
  },
}
