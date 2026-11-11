///|
priv struct LayoutRequest {
  profile : Map[String, String]
  prepareImages : Bool?
  selectionView : SelectionViewRequest?
} derive(@json.FromJson)

///|
priv struct LayoutResponse {
  id : Int32
  revision : Int32
  shapedParagraphs : Int32
  reusedParagraphs : Int32
  reflowedPages : Int32
  reusedPages : Int32
  profile : Map[String, String]
  regions : Array[@layout.DrawingRegion]
  images : Array[String]
  semantics : Array[@layout.SemanticPage]
  comments : Json
  diagnostics : Array[String]
  outlines : Array[@layout.Outline]
  fonts : Array[@layout.FontInfo]
} derive(ToJson)

///|
priv struct HitRequest {
  page : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct NavigateRequest {
  revision : @common.RequestInt
  direction : String
  extend_flag : Bool
  selectionView : Bool?
} derive(@json.FromJson(fields(extend_flag(rename="extend"))))

///|
priv struct ImageKeyRequest {
  key : String
} derive(@json.FromJson)

///|
priv struct ImageSourceRequest {
  key : String
  header : Bool?
} derive(@json.FromJson)

///|
priv struct ImageRequest {
  key : String
  width : @common.RequestInt
  height : @common.RequestInt
  bytes : String
} derive(@json.FromJson)

///|
priv struct PdfLayoutRequest {
  layoutId : @common.RequestInt?
} derive(@json.FromJson)

///|
priv struct PdfOutputRequest {
  outputBytes : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct MarkupOutputRequest {
  revision : @common.RequestInt
  format : String
  outputBytes : @common.RequestInt
} derive(@json.FromJson)

///|
fn Context::layout_document(
  self : Context,
  session : @model.Session,
  input : Json,
) -> Json raise @failure.Failure {
  guard input is { "profile": Object(fields), .. } && fields.length() <= 64 else {
    @failure.reject("invalid-operation", "Explicit font profile is required")
  }
  let command : LayoutRequest = @common.request(input)
  let flow = session.flow()
  if command.prepareImages.unwrap_or(false) {
    let keys = self.docx_image_keys(session, flow)
    self.images.retain(keys)
    let missing = keys.filter(key => {
      try self.images.get(key) catch {
        @failure.Failure(code="missing-image", ..) =>
          !session.prepare_image(key, self.images)
        error => raise error
      } noraise {
        _ => false
      }
    })
    if !missing.is_empty() {
      return { "missingImages": missing }
    }
  }
  self.layout = None
  let result = @layout.paginate(
    self.probe,
    flow,
    command.profile,
    self.images,
    source_versions=true,
  )
  let positioned = session.page_positioned(result, self.probe)
  self.layout = Some(result)
  self.layout_id += 1
  let response : LayoutResponse = {
    id: self.layout_id,
    revision: result.revision,
    shapedParagraphs: result.shapedParagraphs,
    reusedParagraphs: result.reusedParagraphs,
    reflowedPages: result.reflowedPages,
    reusedPages: result.reusedPages,
    profile: result.profile,
    regions: positioned.drawing(self.images, stroke_raster=FractionalStroke),
    images: positioned.drawing_images(self.images),
    semantics: result.semantics(),
    comments: session.comment_overlays(result),
    diagnostics: result.diagnostics,
    outlines: self.probe.outline_resources(),
    fonts: positioned.fonts,
  }
  let encoded = ToJson::to_json(response)
  if command.selectionView is Some(view) && encoded is Object(fields) {
    fields["selectionView"] = self.selection_view(
      session,
      result,
      view.revision.value,
      view.selection.selection(),
      view.formatTable,
      view.describeText,
    )
  }
  encoded
}

///|
let view_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "flow": (context, session, _input) => context.docx_flow(session),
  "layout": (context, session, input) => context.layout_document(session, input),
  "docxSelectionView": (context, session, input) => {
    let layout = context.current_layout(input)
    let view : SelectionViewRequest = @common.request(input)
    context.selection_view(
      session,
      layout,
      view.revision.value,
      view.selection.selection(),
      view.formatTable,
      view.describeText,
    )
  },
  "hitTest": (context, session, input) => {
    let layout = context.current_layout(input)
    guard input is { "x": Number(x, ..), "y": Number(y, ..), .. } else {
      @failure.reject("invalid-position", "Hit coordinates are required")
    }
    let command : HitRequest = @common.request(input)
    ToJson::to_json(
      context.hit_result(session, layout.hit_test(command.page.value, x, y)),
    )
  },
  "caret": (context, session, input) => {
    let layout = context.current_layout(input)
    guard input is { "position": position, .. } else {
      @failure.reject("invalid-position", "Caret position is required")
    }
    let position = field_position(position)
    ToJson::to_json(context.selection_caret(session, layout, position))
  },
  "navigateDocx": (context, session, input) => {
    let layout = context.current_layout(input)
    let command : NavigateRequest = @common.request(input)
    let result = session.navigate(
      command.revision.value,
      layout,
      context.layout_id,
      command.direction,
      extend_selection=command.extend_flag,
    )
    let state = Json(result.state)
    if command.selectionView == Some(true) && state is Object(fields) {
      fields["selectionView"] = context.selection_view(
        session,
        layout,
        command.revision.value,
        result.selection,
        false,
        true,
        cached_formatting?=result.state.formatting.filter(
          @model.FormattingQuery::has_table,
        ),
      )
    }
    { "state": state, "caret": context.hit_result(session, result.hit) }
  },
  "selectionGeometry": (context, session, input) => {
    let layout = context.current_layout(input)
    let selection = field_selection(input)
    ToJson::to_json(context.selection_geometry(session, layout, selection))
  },
  "imagePixels": (context, _session, input) => {
    let command : ImageKeyRequest = @common.request(input)
    guard context.images.get_by_identity(command.key) is Some(image) else {
      @failure.reject("missing-image", "Unknown prepared image identity")
    }
    {
      "width": image.width,
      "height": image.height,
      "bytes": context.output.add(image.rgba),
    }
  },
  "imageBytes": (context, session, input) => {
    let command : ImageSourceRequest = @common.request(input)
    let source = session.image_bytes(command.key)
    if command.header.unwrap_or(false) {
      @common.image_response(context.output, source, None)
    } else {
      { "bytes": context.output.add(source) }
    }
  },
  "image": (context, _session, input) => {
    let command : ImageRequest = @common.request(input)
    context.images.add(
      command.key,
      command.width.value,
      command.height.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
    )
    context.layout = None
    { "key": context.images.get(command.key).identity }
  },
  "exportPdf": (context, session, input) => {
    session.check_idle()
    let command : PdfLayoutRequest = @common.request(input)
    if command.layoutId is Some(id) {
      guard id.value == context.layout_id else {
        @failure.reject(
          "stale-layout", "PDF export requires the displayed layout",
        )
      }
    }
    guard context.layout is Some(layout) else {
      @failure.reject(
        "layout-required", "Create a current layout before PDF export",
      )
    }
    let output : PdfOutputRequest = @common.request(input)
    {
      "bytes": context.output.add(
        @pdf.write(
          {
            ..session.page_positioned(layout, context.probe),
            links: session.page_links(layout),
          },
          context.probe,
          context.images,
          output.outputBytes.value,
          image_smoothing=false,
        ),
      ),
    }
  },
  "exportDocxMarkup": (context, session, input) => {
    let command : MarkupOutputRequest = @common.request(input)
    {
      "bytes": context.output.add(
        session.export_markup(
          command.revision.value,
          command.format,
          command.outputBytes.value,
          layout?=context.layout,
        ),
      ),
    }
  },
}
