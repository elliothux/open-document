///|
fn[T] conversion_budget(
  budget : @pdf.PdfBudget,
  work : () -> T raise,
) -> T raise @failure.Failure {
  let owner = !@pdfcore.sdk_active()
  if owner {
    @pdfcore.sdk_begin(
      budget.streamBytes,
      budget.decodedBytes,
      budget.steps,
      budget.depth,
      budget.objects,
      budget.objectNumber,
      budget.revisions,
    )
  }
  let result = work() catch {
    error => {
      let exceeded = if owner {
        @pdfcore.sdk_end()
      } else {
        @pdfcore.sdk_exhausted()
      }
      if exceeded {
        @failure.reject(
          "limit-exceeded", "PDF conversion exceeds the cumulative operation budget",
        )
      }
      match error {
        @failure.Failure(..) as failure => raise failure
        _ =>
          @failure.reject(
            "conversion-unavailable", "Native Office conversion failed",
          )
      }
    }
  }
  guard !(if owner { @pdfcore.sdk_end() } else { @pdfcore.sdk_exhausted() }) else {
    @failure.reject(
      "limit-exceeded", "PDF conversion exceeds the cumulative operation budget",
    )
  }
  result
}

///|
fn prepare_pages(
  source : @pdf.PdfSession,
  revision : Int32,
  ids : Array[String],
  format : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded : @layout.Images,
  probe : @layout.TextProbe,
  targetProfile : Map[String, String],
  warnings : Array[String],
) -> Array[Page] raise @failure.Failure {
  let families : Map[String, String] = Map([])
  let registered : Map[String, Bool] = Map([])
  for index, info in supplied.font_info() {
    ignore(probe.add_source_font(supplied.font_bytes(index), info.identity))
    registered[info.identity] = true
    families[info.identity] = supplied.font_family(index)
  }
  let pages : Array[Page] = []
  let seen : Map[String, Bool] = Map([])
  for pageIndex, id in ids {
    guard !seen.contains(id) else {
      @failure.reject("invalid-page", "Duplicate PDF conversion page")
    }
    seen[id] = true
    let extracted = source.extract_page(
      revision,
      id,
      supplied,
      profile,
      decoded~,
    )
    defer extracted.close()
    guard extracted.textComplete else {
      @failure.reject(
        "conversion-unavailable",
        "Page \{pageIndex+1}: Unicode mapping is incomplete",
      )
    }
    guard extracted.displayComplete else {
      @failure.reject(
        "conversion-unavailable",
        "Page \{pageIndex+1}: page interpretation is incomplete",
      )
    }
    for index, info in extracted.probe.font_info() {
      if !registered.contains(info.identity) {
        ignore(
          probe.add_source_font(
            extracted.probe.font_bytes(index),
            info.identity,
          ),
        )
        registered[info.identity] = true
      }
      let family = extracted.probe.font_family(index)
      families[info.identity] = if family.is_empty() { "Arial" } else { family }
    }
    let lines = @pdf.read_text_lines(
      extracted,
      families,
      warnings,
      pageIndex + 1,
    )
    let visible = lines.map(@pdf.read_line_text).join("").trim().to_owned()
    if visible.is_empty() &&
      extracted.images.any(image => {
        let (x, y, r, b) = @pdf.read_bounds(image.quad)
        (r - x) * (b - y) >= extracted.width * extracted.height * 0.8
      }) {
      @failure.reject(
        "ocr-required",
        "Page \{pageIndex+1}: scanned image requires OCR before editable conversion",
      )
    }
    let tables = @pdf.read_tables(extracted.paths, lines)
    if !tables.is_empty() {
      @pdf.read_warning(
        warnings,
        "Page \{pageIndex+1}: recognized table borders were normalized to solid black native grid lines",
      )
    }
    let outside = lines.filter(line => {
      !tables.any(table => @pdf.read_line_in_table(line, table))
    })
    let images : Array[@pdf.PdfExtractedImage] = []
    for image in extracted.images {
      if image.clipped {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: clipped image was omitted",
        )
        continue
      }
      let reason = try {
        ignore(image_box(image))
        ignore(image_bytes(image))
        if format == "docx" && image.rgba.is_empty() {
          "DOCX image needs decoded source pixels"
        } else {
          ""
        }
      } catch {
        @failure.Failure(message~, ..) => message
      }
      if !reason.is_empty() {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: image omitted: " + reason,
        )
        continue
      }
      images.push(image)
      if image.annotation {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: an annotation appearance became an ordinary picture",
        )
      }
    }
    if format == "xlsx" {
      guard !tables.is_empty() else {
        @failure.reject(
          "conversion-unavailable",
          "Page \{pageIndex+1}: no table with explicit cell boundaries was found",
        )
      }
      if !outside.is_empty() || !images.is_empty() {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: content outside recognized tables was omitted from the workbook",
        )
      }
      if tables.any(table => {
          table.ys.windows(2).any(pair => pair[1] - pair[0] > 409.5) ||
          table.xs.windows(2).any(pair => pair[1] - pair[0] > 1200)
        }) {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: worksheet dimensions were limited by Excel row or column limits",
        )
      }
    }
    if format == "docx" {
      if Array::makei(extracted.paths.length(), index => index).any(index => {
          !tables.any(table => table.paths.contains(index))
        }) {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: non-table vector graphics were omitted",
        )
      }
      if outside.is_empty() &&
        tables.is_empty() &&
        images.is_empty() &&
        (
          !extracted.glyphs.is_empty() ||
          !extracted.images.is_empty() ||
          !extracted.paths.is_empty()
        ) {
        @failure.reject(
          "conversion-unavailable",
          "Page \{pageIndex+1}: no editable text, table or picture could be reconstructed",
        )
      }
      for index, line in outside {
        for other in outside[index + 1:] {
          if (line.y - other.y).abs() < line.height * 0.5 {
            @failure.reject(
              "conversion-unavailable",
              "Page \{pageIndex+1}: multiple text columns cannot be reliably reconstructed as single-column Word paragraphs",
            )
          }
        }
      }
    }
    if pageIndex > 0 &&
      (extracted.width != pages[0].width || extracted.height != pages[0].height) {
      @pdf.read_warning(
        warnings,
        "Page \{pageIndex+1}: mixed page dimensions were fitted to the first target page size",
      )
    }
    let page : Page = {
      source: id,
      width: extracted.width,
      height: extracted.height,
      lines: outside,
      tables,
      images,
      paths: extracted.paths.copy(),
    }
    if format == "pptx" {
      ignore(presentation_shapes(page, 1, 0, 0, warnings, pageIndex + 1))
      if lines.any(line => line.runs.length() > 1) {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: styling within a line was normalized to its first run",
        )
      }
      if !images.is_empty() &&
        (!lines.is_empty() || !extracted.paths.is_empty()) {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: objects were grouped by content type; overlapping content may have a different drawing order",
        )
      }
    }
    for line in lines {
      for run in line.runs {
        targetProfile[run.font] = run.identity
        let primary = probe.font_index(run.identity)
        let shaped = probe.shape(run.text, run.size, "en", primary~)
        guard shaped.diagnostics.is_empty() else {
          @failure.reject(
            "conversion-unavailable",
            "Page \{pageIndex+1}: target font cannot represent the source text",
          )
        }
        if shaped.glyphs.any(glyph => glyph.font != primary) {
          @pdf.read_warning(
            warnings,
            "Page \{pageIndex+1}: target text uses a fallback font for characters missing from a source subset",
          )
        }
      }
    }
    pages.push(page)
  }
  if !targetProfile.contains("*") {
    let fonts = probe.font_info()
    if !fonts.is_empty() {
      targetProfile["*"] = fonts[0].identity
    }
  }
  pages
}

///|
/// Convert committed PDF content through the native target format sessions.
/// Warnings require explicit loss acceptance before any bytes are delivered.
pub fn convert(
  source : @pdf.PdfSession,
  revision : Int32,
  ids : Array[String],
  format : String,
  acceptLoss : Bool,
  budget : @archive.Budget,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded~ : @layout.Images,
) -> ConversionResult raise @failure.Failure {
  guard ["docx", "xlsx", "pptx"].contains(format) &&
    !ids.is_empty() &&
    ids.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "Choose PDF pages and a supported Office format",
    )
  }
  guard source.revision == revision else {
    @failure.reject("stale-revision", "PDF revision changed")
  }
  let probe = @layout.TextProbe::new()
  defer probe.close()
  let warnings : Array[String] = []
  let mapping : Array[PageMap] = []
  let result = conversion_budget(source.budget, () => {
    let targetProfile = profile.copy()
    let pages = prepare_pages(
      source, revision, ids, format, supplied, profile, decoded, probe, targetProfile,
      warnings,
    )
    @pdf.read_warning(
      warnings, "Source font families were retained; PDF fonts are not embedded in the Office output and may be substituted when opened",
    )
    @pdf.read_warning(
      warnings,
      if format == "docx" {
        "PDF positioning was rebuilt as reflowable paragraphs; pagination and spacing may differ"
      } else if format == "xlsx" {
        "PDF page coordinates were converted to worksheet dimensions; source formulas cannot be recovered"
      } else {
        "Source font names were retained but PDF-embedded fonts are not embedded in the presentation"
      },
    )
    if !acceptLoss && !warnings.is_empty() {
      return {
        revision,
        format,
        status: "needs-acceptance",
        reason: "Review the page-specific losses before exporting",
        warnings,
        pages: Array::makei(ids.length(), index => {
          source: ids[index],
          target: index + 1,
        }),
        bytes: None,
      }
    }
    let cap = source.budget.outputBytes.min(budget.output_bytes).min(67108864)
    let budget = { ..budget, output_bytes: cap, }
    let (bytes, targets) = match format {
      "docx" => write_docx(pages, budget, probe, targetProfile, warnings)
      "xlsx" => write_xlsx(pages, budget, probe, targetProfile)
      _ => write_pptx(pages, budget, probe, targetProfile, warnings)
    }
    guard bytes.length() <= cap else {
      @failure.reject(
        "limit-exceeded", "Office output exceeds the PDF output budget",
      )
    }
    mapping.append(targets)
    {
      revision,
      format,
      status: if warnings.is_empty() {
        "success"
      } else {
        "completed-with-loss"
      },
      reason: "",
      warnings,
      pages: targets,
      bytes: Some(bytes),
    }
  }) catch {
    @failure.Failure(message~, ..) =>
      {
        revision,
        format,
        status: "failed",
        reason: message,
        warnings,
        pages: mapping,
        bytes: None,
      }
  }
  result
}
