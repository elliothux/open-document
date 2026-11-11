///|
let page_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "cropPdfPage": (_context, session, input) => {
    let command : CropPageRequest = @common.request(input)
    session
    .crop_page(
      command.revision.value,
      command.page,
      command.x.value,
      command.y.value,
      command.width.value,
      command.height.value,
    )
    .stringify()
  },
  "resizePdfPage": (_context, session, input) => {
    let command : ResizePageRequest = @common.request(input)
    session
    .resize_page(
      command.revision.value,
      command.page,
      command.width.value,
      command.height.value,
      command.scaleContent,
      command.anchor,
    )
    .stringify()
  },
  "insertPdfPages": (_context, session, input) => {
    let command : ImportPagesRequest = @common.request(input)
    session
    .insert_pages(
      command.revision.value,
      @common.byte_input(command.bytes, @model.PdfBudget::default().fileBytes),
      command.pages.value,
      command.index.value,
    )
    .stringify()
  },
  "replacePdfPages": (_context, session, input) => {
    let command : ReplacePagesRequest = @common.request(input)
    session
    .insert_pages(
      command.revision.value,
      @common.byte_input(command.bytes, @model.PdfBudget::default().fileBytes),
      command.pages.value,
      command.index.value,
      replace=command.replace.value,
    )
    .stringify()
  },
  "insertBlankPdfPage": (_context, session, input) => {
    let command : BlankPageRequest = @common.request(input)
    session
    .insert_blank(
      command.revision.value,
      command.index.value,
      command.width.value,
      command.height.value,
    )
    .stringify()
  },
  "extractPdfPages": (context, session, input) => {
    let command : PageOrderRequest = @common.request(input)
    let result : PdfBytesOutput = {
      revision: command.revision.value,
      bytes: context.output.add(
        session.extract_pages(command.revision.value, command.pages.value),
      ),
    }
    ToJson::to_json(result).stringify()
  },
  "reorderPdfPages": (_context, session, input) => {
    let command : PageOrderRequest = @common.request(input)
    session.reorder(command.revision.value, command.pages.value).stringify()
  },
  "deletePdfPages": (_context, session, input) => {
    let command : PageOrderRequest = @common.request(input)
    session
    .delete_pages(command.revision.value, command.pages.value)
    .stringify()
  },
  "rotatePdfPages": (_context, session, input) => {
    let command : RotatePagesRequest = @common.request(input)
    let degrees = command.degrees.value
    guard degrees >= -36000 &&
      degrees <= 36000 &&
      degrees == degrees.to_int().to_double() else {
      @failure.reject(
        "invalid-operation", "PDF rotation requires bounded integer degrees",
      )
    }
    session
    .rotate_pages(command.revision.value, command.pages.value, degrees.to_int())
    .stringify()
  },
  "splitPdfFiles": (context, session, input) => {
    let command : SplitFilesRequest = @common.request(input)
    let groups = command.groups.value.map(group => group.value)
    let result : PdfSplitOutput = {
      revision: command.revision.value,
      files: session
      .split_files(command.revision.value, groups)
      .map(file => { name: file.0, bytes: context.output.add(file.1), }),
    }
    ToJson::to_json(result).stringify()
  },
  "exportPdfText": (context, session, input) => {
    let command : ExportTextRequest = @common.request(input)
    let (bytes, warnings) = session.export_text(
      command.revision.value,
      command.pages.value,
      command.format,
      context.probe,
      command.profile.value,
      decoded=context.images,
    )
    let result : PdfExportOutput = {
      revision: command.revision.value,
      bytes: context.output.add(bytes),
      warnings,
    }
    ToJson::to_json(result).stringify()
  },
  "setPdfMetadata": (_context, session, input) => {
    let command : MetadataRequest = @common.request(input)
    session.set_metadata(command.revision.value, command.fields).stringify()
  },
  "splitPdfPage": (_context, session, input) => {
    let command : SplitPageRequest = @common.request(input)
    session
    .split_page(
      command.revision.value,
      split_page_key(command.page),
      command.regions.value,
    )
    .stringify()
  },
  "splitPdfPageGrid": (_context, session, input) => {
    let command : SplitGridRequest = @common.request(input)
    session
    .split_page_grid(
      command.revision.value,
      split_page_key(command.page),
      command.columns.value,
      command.rows.value,
    )
    .stringify()
  },
  "nupPdfPages": (_context, session, input) => {
    let command : NupPagesRequest = @common.request(input)
    session
    .nup_pages(
      command.revision.value,
      command.pages.value,
      command.columns.value,
      command.rows.value,
      command.width.value,
      command.height.value,
    )
    .stringify()
  },
  "renderPdfPage": (context, session, input) => {
    let command : RenderPageRequest = @common.request(input)
    session.render_response(
      command.revision.value,
      command.page,
      context.probe,
      command.profile.value,
      context.images,
      activate=command.activate.unwrap_or(true),
      reuse=command.reuse.unwrap_or(false),
      outline_delta=value => context.outlines.encode_string(value),
    )
  },
  "imagePdf": (context, session, input) => {
    if input is { "size": Null, .. } {
      @failure.reject("invalid-operation", "Image size must be an object")
    }
    let command : ImageReadRequest = @common.request(input)
    let size = command.size.map(size => (size.width.value, size.height.value))
    let (kind, bytes, width, height) = session.image(
      command.layoutId.value,
      command.key,
      context.images,
      size~,
    )
    let image : PdfImageOutput = {
      kind,
      bytes: context.output.add(bytes),
      width,
      height,
      header: if kind == "jpeg" {
        Some(@common.image_header(bytes))
      } else {
        None
      },
    }
    ToJson::to_json(image).stringify()
  },
  "decodedImagePdf": (context, session, input) => {
    let command : ImageDecodeRequest = @common.request(input)
    session.decoded_image(
      command.layoutId.value,
      command.key,
      command.width.value,
      command.height.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
      context.images,
    )
    let image = context.images.get(command.key)
    let result : PdfImageOutput = {
      kind: "rgba",
      bytes: context.output.add(image.rgba),
      width: image.width,
      height: image.height,
      header: None,
    }
    ToJson::to_json(result).stringify()
  },
}
