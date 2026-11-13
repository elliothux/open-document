///|
fn PdfSession::page(
  self : PdfSession,
  id : String,
) -> SourcePage raise @failure.Failure {
  self.check(self.revision)
  for page in self.pages {
    if page.id == id {
      return page
    }
  }
  @failure.reject("invalid-page", "Unknown PDF page: " + id)
}

///|
fn PdfSession::build_display(
  self : PdfSession,
  id : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
  extract~ : Bool = false,
) -> PageDisplay raise @failure.Failure {
  if self.ranged is Some(source) {
    return source.with_objects(self.document, id, check_source => {
      self.interpret_display(
        id,
        supplied,
        profile,
        images,
        extract~,
        check_source~,
      )
    })
  }
  self.interpret_display(id, supplied, profile, images, extract~)
}

///|
fn PdfSession::interpret_display(
  self : PdfSession,
  id : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
  extract~ : Bool,
  check_source~ : () -> Unit raise @failure.Failure = () => (),
) -> PageDisplay raise @failure.Failure {
  let page = self.page(id)
  let probe = @layout.TextProbe::new(embedded_faces=true)
  errdefer probe.close()
  pdf_bound(self.budget, () => {
    let context : ContentContext = {
      extraction: if extract {
        Some(PdfExtractionData::new())
      } else {
        None
      },
      sources: [],
      collectSource: true,
      session: self,
      page,
      probe,
      supplied,
      profile,
      images,
      commands: [],
      diagnostics: [],
      spans: [],
      chunks: [],
      units: 0,
      textComplete: true,
      displayComplete: true,
      fonts: Map([]),
      nativeOutlines: Map([]),
      strokeGlyphs: Map([]),
      nativeOutlineBytes: Ref(0),
      preparedStrokePoints: Ref(0),
      colors: Map([]),
      optional: None,
      imageKeys: [],
      jpeg: Map([]),
      flateImages: Map([]),
      forms: Map([]),
      marked: [],
      nesting: 0,
    }
    let state : GraphicsState = {
      matrix: page.matrix,
      fill: "000000",
      stroke: "000000",
      width: 1,
      style: @layout.DrawStyle::default(),
      text: @pdflite.pdf_content_initial_text_state(),
      font: None,
      clips: 0,
      fillSpace: GrayColor,
      strokeSpace: GrayColor,
      softMask: None,
      fillPattern: None,
    }
    context.scope(
      @layout.ClipRect({ x: 0, y: 0, width: page.width, height: page.height, }),
    )
    context.commands.push(
      @layout.FillRect(
        { x: 0, y: 0, width: page.width, height: page.height, color: "ffffff", },
        screen_fractional=false,
      ),
    )
    let object = resolve(self.document, @syntax.PdfIndirect(page.number))
    check_source()
    try {
      let grouped = page_transparency_group(context, object, page.resources)
      let start = context.commands.length()
      let (bytes, origin) = page_source(self.document, raw(object, "Contents"))
      interpret(
        context,
        bytes,
        page.resources,
        id,
        state,
        0,
        origin=Some(origin),
      )
      if grouped {
        @pdfcore.sdk_check(context.commands.length() - start)
        let commands = context.commands[start:].to_owned()
        input_layer_budget(commands, 1)
        context.commands.truncate(start)
        context.commands.push(@layout.Layer(1, commands))
      }
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => {
        context.diagnostics.push(message)
        context.textComplete = false
        context.displayComplete = false
        context.commands.clear()
        context.imageKeys.clear()
        context.jpeg.clear()
        context.flateImages.clear()
        images.clear()
        context.commands.push(
          @layout.FillRect(
            {
              x: 0,
              y: 0,
              width: page.width,
              height: page.height,
              color: "ffffff",
            },
            screen_fractional=false,
          ),
        )
        context.nesting = 0
      }
      @pdfcore.PdfError::FlateOutputLimitExceeded(_) =>
        @failure.reject("limit-exceeded", "PDF page stream exceeds budget")
      _ => {
        context.diagnostics.push("Malformed PDF page content")
        context.textComplete = false
        context.displayComplete = false
        context.commands.clear()
        context.imageKeys.clear()
        context.jpeg.clear()
        context.flateImages.clear()
        images.clear()
        context.commands.push(
          @layout.FillRect(
            {
              x: 0,
              y: 0,
              width: page.width,
              height: page.height,
              color: "ffffff",
            },
            screen_fractional=false,
          ),
        )
        context.nesting = 0
      }
    }
    while context.nesting > 0 {
      context.restore()
    }
    let bodySpans = context.spans.copy()
    let bodyText = context.chunks.join("")
    let bodyComplete = context.textComplete
    context.marked.clear()
    context.collectSource = false
    render_appearances(context, state)
    check_source()
    let imageBytes = context.fit_image_budget()
    let outlines : Map[String, @layout.Outline] = Map([])
    for outline in probe.outline_resources() {
      outlines[outline.key] = outline
    }
    for (_, outline) in context.nativeOutlines {
      outlines[outline.key] = outline
    }
    let outlines = outlines.iter().map(pair => pair.1).to_array()
    guard outlines.fold(init=0L, (sum, item) => {
        sum + item.path.length().to_int64()
      }) <=
      8388608 else {
      @failure.reject("limit-exceeded", "PDF page outlines exceed budget")
    }
    @layout.annotate_gradient_clips(context.commands, device=true)
    {
      response: None,
      extraction: context.extraction,
      sources: context.sources,
      profile: profile.copy(),
      supplied_fonts: Json(supplied.font_info()).stringify(),
      resources: images,
      imageBytes,
      page: id,
      id: self.layoutId + 1,
      revision: self.revision,
      region: {
        width: page.width,
        height: page.height,
        strokeRaster: CoverageStroke,
        glyphRaster: CoverageGlyphs,
        commands: context.commands,
      },
      text: bodyText,
      spans: bodySpans,
      textComplete: bodyComplete,
      displayComplete: context.displayComplete,
      diagnostics: context.diagnostics,
      images: context.imageKeys,
      jpeg: context.jpeg,
      flateImages: context.flateImages,
      probe,
      outlines,
    }
  })
}

///|
/// Retain a bounded page view; background rendering preserves active selection.
fn PdfSession::retain_display(
  self : PdfSession,
  revision : Int32,
  page : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
  activate~ : Bool = true,
  reuse~ : Bool = false,
) -> (PageDisplay, Bool) raise @failure.Failure {
  self.check(revision)
  let fonts = Json(supplied.font_info()).stringify()
  let cached = self.views
    .values()
    .find_first(view => {
      view.page == page &&
      view.revision == revision &&
      view.supplied_fonts == fonts &&
      profile.length() == view.profile.length() &&
      profile.iter().all(pair => view.profile.get(pair.0) == Some(pair.1))
    })
  if reuse {
    if cached is Some(view) {
      if activate {
        self.display = Some(view)
        self.current = page
        self.selection = (0, 0)
      }
      return (view, true)
    }
  }
  let temporary = @layout.Images::new()
  guard pdf_layout_serial.val < 2147483647 else {
    @failure.reject("limit-exceeded", "PDF drawing identity exhausted")
  }
  let candidate = cached.unwrap_or_else(() => {
    self.build_display(page, supplied, profile, temporary)
  })
  errdefer (if cached is None { candidate.probe.close() })
  let mut retained : Int64 = candidate.imageBytes.to_int64()
  let mut count = 1
  let mut previous : Int32? = None
  for id, view in self.views {
    if view.page == page {
      previous = Some(id)
    } else {
      retained += view.imageBytes.to_int64()
      count += 1
    }
  }
  guard count <= 9 && retained <= 16777216 else {
    @failure.reject(
      "limit-exceeded", "Release PDF views before retaining more than nine pages or 16 MiB of images",
    )
  }
  let display = { ..candidate, id: pdf_layout_serial.val + 1, }
  if previous is Some(id) {
    if cached is None {
      self.views[id].probe.close()
    }
    self.views.remove(id)
  }
  self.views[display.id] = display
  self.layoutId = display.id
  pdf_layout_serial.val = display.id
  if activate {
    self.display = Some(display)
    self.current = page
    self.selection = (0, 0)
  } else if self.display is Some(active) && active.page == page {
    self.display = Some(display)
  }
  images.clear()
  for key in display.images {
    if !display.jpeg.contains(key) && !display.flateImages.contains(key) {
      let image = display.resources.get(key)
      images.add(key, image.width, image.height, image.rgba)
    }
  }
  (display, false)
}

///|
fn display_content(display : PageDisplay) -> (PdfDisplayContent, Json) {
  if display.response is Some(response) {
    return response
  }
  let content : PdfDisplayContent = {
    revision: display.revision,
    page: display.page,
    regions: [
      display.region.encode(
        Json::array(pdf_display_commands(display.region.commands)),
      ),
    ],
    images: display.images,
    text: display.text,
    spans: display.spans.map(TextSpan::display_span),
    textComplete: display.textComplete,
    displayComplete: display.displayComplete,
    diagnostics: display.diagnostics,
  }
  let response = (content, Json(display.outlines))
  display.response = Some(response)
  response
}

///|
/// Serialize page content once; layout identity and reuse status remain per-call.
pub fn PdfSession::render_response(
  self : PdfSession,
  revision : Int32,
  page : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
  activate~ : Bool = true,
  reuse~ : Bool = false,
  outline_delta? : (Json) -> String,
) -> String raise @failure.Failure {
  let (display, reused) = self.retain_display(
    revision,
    page,
    supplied,
    profile,
    images,
    activate~,
    reuse~,
  )
  let (content, outlines) = display_content(display)
  self.encode_display(display.id, reused, content, outlines, outline_delta?)
}

///|
fn PdfSession::encode_display(
  self : PdfSession,
  id : Int32,
  reused : Bool,
  content : PdfDisplayContent,
  outlines : Json,
  outline_delta? : (Json) -> String,
) -> String {
  let body = match self.encodedDisplay {
    Some((previous, body)) if physical_equal(previous, content) => body
    _ => {
      self.encodedDisplay = None
      let encoded = Json(content).stringify()
      let body = encoded[1:].to_owned()
      // One cached string, at most 8 MiB even with UTF-16 storage; larger pages still render.
      if body.length() <= 4194304 {
        self.encodedDisplay = Some((content, body))
      }
      body
    }
  }
  let outlines = match outline_delta {
    Some(encode) => encode(outlines)
    None => outlines.stringify()
  }
  "{\"id\":\{id},\"reused\":\{reused},\"outlines\":" + outlines + "," + body
}

///|
fn PdfSession::current_display(
  self : PdfSession,
  id : Int32,
) -> PageDisplay raise @failure.Failure {
  self.check(self.revision)
  guard self.views.get(id) is Some(display) &&
    display.id == id &&
    display.revision == self.revision else {
    @failure.reject("stale-layout", "PDF geometry requires the displayed page")
  }
  display
}

///|
/// Extract in content order without changing the displayed page or its selection.
pub fn PdfSession::extract(
  self : PdfSession,
  revision : Int32,
  page : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> PdfText raise @failure.Failure {
  self.check(revision)
  if self.display is Some(display) &&
    display.page == page &&
    display.revision == revision {
    return text_result(display)
  }
  let display = self.build_display(
    page,
    supplied,
    profile,
    @layout.Images::new(),
  )
  let result = text_result(display)
  display.probe.close()
  result
}

///|
fn text_result(display : PageDisplay) -> PdfText {
  {
    page: display.page,
    revision: display.revision,
    text: display.text,
    spans: display.spans,
    complete: display.textComplete,
    diagnostics: display.diagnostics,
  }
}

///|
pub const SearchTextUnits : Int32 = 1024

///|
pub fn PdfSession::search(
  self : PdfSession,
  revision : Int32,
  page : String,
  query : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> PdfSearch raise @failure.Failure {
  self.check(revision)
  guard !query.is_empty() && query.length() <= SearchTextUnits else {
    @failure.reject(
      "limit-exceeded",
      "PDF query must contain 1 through \{SearchTextUnits} UTF-16 units",
    )
  }
  check_pdf_text(query)
  let temporary = !(self.display is Some(display) &&
    display.page == page &&
    display.revision == revision)
  let display = if temporary {
    self.build_display(page, supplied, profile, @layout.Images::new())
  } else {
    self.display.unwrap()
  }
  errdefer (if temporary { display.probe.close() })
  let result = search_result(display, query)
  if temporary {
    display.probe.close()
  }
  result
}

///|
fn search_result(
  display : PageDisplay,
  query : String,
) -> PdfSearch raise @failure.Failure {
  let hits : Array[PdfSearchHit] = []
  let visible = crop_visible_ranges(display)
  let mut offset = 0
  while offset + query.length() <= display.text.length() {
    let end = offset + query.length()
    if display.text[offset:end] == query &&
      !display.spans.any(span => {
        (!span.mapped || !visible.contains((span.start, span.end))) &&
        span.start < end &&
        span.end > offset
      }) {
      guard hits.length() < 10000 else {
        @failure.reject("limit-exceeded", "PDF search result exceeds budget")
      }
      hits.push({
        start: offset,
        end,
        quads: display.spans
        .filter(span => {
          span.cropVisible && span.start < end && span.end > offset
        })
        .map(span => span.quad),
      })
      offset = end
    } else {
      offset += 1
    }
  }
  {
    page: display.page,
    revision: display.revision,
    complete: display.textComplete,
    hits,
    diagnostics: display.diagnostics,
  }
}

///|
pub fn PdfSession::select_text(
  self : PdfSession,
  layout_id : Int32,
  anchor : Int32,
  focus : Int32,
) -> PdfSelection raise @failure.Failure {
  let display = self.current_display(layout_id)
  guard anchor >= 0 &&
    focus >= 0 &&
    anchor <= display.text.length() &&
    focus <= display.text.length() else {
    @failure.reject("invalid-selection", "PDF selection is outside page text")
  }
  for offset in [anchor, focus] {
    guard offset == 0 ||
      offset == display.text.length() ||
      !(display.text[offset - 1].to_int() >= 0xd800 &&
      display.text[offset - 1].to_int() <= 0xdbff &&
      display.text[offset].to_int() >= 0xdc00 &&
      display.text[offset].to_int() <= 0xdfff) else {
      @failure.reject(
        "invalid-selection", "PDF selection splits a surrogate pair",
      )
    }
  }
  self.selection = (anchor, focus)
  self.textRange = None
  self.display = Some(display)
  self.current = display.page
  let start = anchor.min(focus)
  let end = anchor.max(focus)
  {
    page: display.page,
    layoutId: layout_id,
    revision: self.revision,
    anchor,
    focus,
    quads: display.spans
    .filter(span => span.cropVisible && span.start < end && span.end > start)
    .map(span => span.quad),
  }
}

///|
pub fn PdfSession::selected_text(
  self : PdfSession,
  layout_id : Int32,
) -> String raise @failure.Failure {
  let display = self.current_display(layout_id)
  let (a, b) = self.selection
  let start = a.min(b)
  let end = a.max(b)
  visible_text(display, start, end)
}

///|
pub fn PdfSession::hit(
  self : PdfSession,
  layout_id : Int32,
  x : Double,
  y : Double,
) -> PdfHit raise @failure.Failure {
  let display = self.current_display(layout_id)
  guard !x.is_nan() && !y.is_nan() && !x.is_inf() && !y.is_inf() else {
    @failure.reject("invalid-position", "PDF hit requires finite coordinates")
  }
  let mut best : (TextSpan, Double, Double)? = None
  for span in display.spans {
    if !span.cropVisible || span.end <= span.start {
      continue
    }
    let q = span.quad
    let a = q[6] - q[0]
    let b = q[7] - q[1]
    let c = q[2] - q[0]
    let d = q[3] - q[1]
    let determinant = a * d - b * c
    if determinant.abs() < 0.000000001 {
      continue
    }
    let px = x - q[0]
    let py = y - q[1]
    let u = (d * px - c * py) / determinant
    let v = (-b * px + a * py) / determinant
    let distance = (u - u.max(0).min(1)).abs() + (v - v.max(0).min(1)).abs()
    if best is None || distance < best.unwrap().1 {
      best = Some((span, distance, u))
    }
  }
  let offset = match best {
    Some((span, _, u)) => if u < 0.5 { span.start } else { span.end }
    None => 0
  }
  { page: display.page, layoutId: layout_id, revision: self.revision, offset, }
}

///|
pub fn PdfSession::image(
  self : PdfSession,
  layout_id : Int32,
  key : String,
  images : @layout.Images,
  size~ : (Int32, Int32)? = None,
) -> (String, Bytes, Int32, Int32, Bool) raise @failure.Failure {
  let display = self.current_display(layout_id)
  guard display.images.contains(key) else {
    @failure.reject("missing-image", "Unknown PDF page image")
  }
  let image = display.resources.get(key) catch {
    @failure.Failure(code="missing-image", ..) as missing => {
      let (width, height, output) = if display.flateImages.get(key)
        is Some(flate) &&
        flate.preview is Some((width, height)) {
        (
          width,
          height,
          pdf_bound(self.budget, () => flate.raster(width, height)),
        )
      } else {
        guard display.jpeg.get(key) is Some(jpeg) else { raise missing }
        let (width, height) = jpeg.display_size()
        guard jpeg.core_pixels(self.budget) is Some(output) else {
          if size is None {
            return (
              "jpeg",
              jpeg.bytes,
              width,
              height,
              jpeg.needs_source_samples(),
            )
          }
          raise missing
        }
        (width, height, output)
      }
      images.add(key, width, height, output)
      display.resources.add(key, width, height, output)
      display.resources.get(key)
    }
    error => raise error
  }
  if size is Some((width, height)) {
    let rgba = pdf_bound(self.budget, () => resized_rgba(image, width, height))
    return ("rgba", rgba, width, height, false)
  }
  ("rgba", image.rgba, image.width, image.height, false)
}

///|
pub fn PdfSession::decoded_image(
  self : PdfSession,
  layout_id : Int32,
  key : String,
  width : Int32,
  height : Int32,
  rgba : Bytes,
  images : @layout.Images,
) -> Unit raise @failure.Failure {
  let display = self.current_display(layout_id)
  guard display.jpeg.get(key) is Some(jpeg) &&
    (width, height) == jpeg.display_size() &&
    width.to_int64() *
    height.to_int64() *
    (if jpeg.needs_source_samples() { 12L } else { 4L }) ==
    rgba.length().to_int64() else {
    @failure.reject("invalid-image", "JPEG decoder dimensions do not match PDF")
  }
  let output = pdf_bound(self.budget, () => jpeg.pixels(rgba))
  display.resources.add(key, width, height, output)
  images.add(key, width, height, output)
}

///|
/// Release a page view and reject subsequent geometry or image requests for it.
pub fn PdfSession::release_view(self : PdfSession, id : Int32) -> Unit {
  if self.views.get(id) is Some(view) {
    view.probe.close()
    self.views.remove(id)
    self.encodedDisplay = None
    if self.display is Some(active) && active.id == id {
      self.display = None
      self.selection = (0, 0)
    }
  }
}
