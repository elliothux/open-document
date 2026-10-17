///|
pub struct Foundation {
  probe : @layout.TextProbe
  mut docx : @docx.Session?
  mut xlsx : @xlsx.Session?
  mut pptx : @pptx.Session?
  mut pdf : @pdf.PdfSession?
  mut closed : Bool
  mut layout : @layout.Layout?
  images : @layout.Images
  mut layout_id : Int
  mut xlsx_print : (@layout.PositionedDocument, Int, Int)?
}

///|
pub fn new_foundation() -> Foundation {
  {
    probe: @layout.TextProbe::new(),
    docx: None,
    xlsx: None,
    pptx: None,
    pdf: None,
    closed: false,
    layout: None,
    images: @layout.Images::new(),
    layout_id: 0,
    xlsx_print: None,
  }
}

///|
fn field_selection(json : Json) -> @docx.Selection raise @failure.Failure {
  guard json is { "selection": { "anchor": anchor, "focus": focus, .. }, .. } else {
    @failure.reject("invalid-operation", "Explicit selection is required")
  }
  { anchor: field_position(anchor), focus: field_position(focus), }
}

///|
fn field_position(json : Json) -> @docx.Position raise @failure.Failure {
  {
    paragraph: field_int(json, "paragraph"),
    offset: field_int(json, "offset"),
    affinity: field_string(json, "affinity"),
    bidiLevel: if json is Object(fields) && fields.contains("bidiLevel") {
      Some(field_int(json, "bidiLevel"))
    } else {
      None
    },
    frameStart: if json is Object(fields) && fields.contains("frameStart") {
      Some(field_int(json, "frameStart"))
    } else {
      None
    },
  }
}

///|
fn Foundation::current_layout(
  self : Foundation,
  request : Json,
) -> @layout.Layout raise @failure.Failure {
  guard field_int(request, "layoutId") == self.layout_id &&
    self.layout is Some(layout) else {
    @failure.reject(
      "stale-layout", "Geometry requires the current displayed layout",
    )
  }
  layout
}

///|
fn input_bytes(json : Json, ceiling : Int) -> Bytes raise @failure.Failure {
  let encoded = field_string(json, "bytes")
  guard encoded.length().to_int64() <= (ceiling.to_int64() + 2) / 3 * 4 else {
    @failure.reject("limit-exceeded", "Encoded byte input exceeds budget")
  }
  let bytes = @base64.decode(encoded) catch {
    _ => @failure.reject("invalid-operation", "Invalid base64 byte input")
  }
  guard bytes.length() <= ceiling else {
    @failure.reject("limit-exceeded", "Byte input exceeds budget")
  }
  bytes
}

///|
fn Foundation::dispatch(
  self : Foundation,
  request : Json,
) -> Json raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Foundation session is closed")
  }
  let operation = field_string(request, "operation")
  match operation {
    "docxPictures" | "editDocxPicture" | "docxPictureResize" =>
      self.picture_operation(operation, request)
    "budget" => {
      let budget = @archive.Budget::default()
      {
        "fileBytes": budget.file_bytes,
        "entryBytes": budget.entry_bytes,
        "totalBytes": budget.total_bytes,
        "retainedBytes": budget.retained_bytes,
        "entries": budget.entries,
        "xmlDepth": budget.xml_depth,
        "outputBytes": budget.output_bytes,
      }
    }
    "shape" => {
      guard request is { "size": Number(size, ..), .. } else {
        @failure.reject("invalid-operation", "Invalid font size")
      }
      self.probe
      .shape(
        field_string(request, "text"),
        size,
        field_string(request, "language"),
      )
      .to_json()
    }
    "openDocx" | "createDocx" => {
      guard self.docx is None &&
        self.xlsx is None &&
        self.pptx is None &&
        self.pdf is None else {
        @failure.reject("invalid-operation", "DOCX session is already open")
      }
      guard request is { "budget": budget, .. } else {
        @failure.reject("invalid-budget", "Explicit budget is required")
      }
      let budget : @archive.Budget = {
        file_bytes: field_int(budget, "fileBytes"),
        entry_bytes: field_int(budget, "entryBytes"),
        total_bytes: field_int(budget, "totalBytes"),
        retained_bytes: field_int(budget, "retainedBytes"),
        entries: field_int(budget, "entries"),
        xml_depth: field_int(budget, "xmlDepth"),
        output_bytes: field_int(budget, "outputBytes"),
      }
      let session = if operation == "createDocx" {
        @docx.Session::create(budget)
      } else {
        @docx.Session::open(
          input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
          budget,
        )
      }
      self.docx = Some(session)
      session.query()
    }
    "openXlsx"
    | "createXlsx"
    | "importXlsxDelimited"
    | "exportXlsxCsv"
    | "editXlsxSheet"
    | "autoFitXlsx"
    | "formatXlsxCells"
    | "captureXlsxFormat"
    | "applyXlsxFormat"
    | "queryXlsx"
    | "duplicatesXlsx"
    | "textColumnsXlsx"
    | "selectXlsx"
    | "replaceXlsx"
    | "findXlsx"
    | "replaceXlsxMatches"
    | "undoXlsx"
    | "redoXlsx"
    | "saveXlsx"
    | "viewportXlsx"
    | "hitXlsx"
    | "selectionXlsx"
    | "fillPreviewXlsx"
    | "navigateXlsx"
    | "copyXlsx"
    | "pasteXlsx"
    | "clearXlsx"
    | "printXlsx"
    | "exportXlsxPdf" => self.xlsx_operation(operation, request)
    "openPptx"
    | "createPptx"
    | "queryPptx"
    | "followPptxHyperlink"
    | "findPptx"
    | "replacePptxMatches"
    | "selectPptx"
    | "replacePptx"
    | "deletePptx"
    | "editPptxObjects"
    | "editPptxSlides"
    | "undoPptx"
    | "redoPptx"
    | "savePptx"
    | "layoutPptx"
    | "hitPptx"
    | "selectionPptx"
    | "navigatePptx"
    | "beginPptx"
    | "transformPptx"
    | "dragPptx"
    | "finishPptx"
    | "cancelPptx"
    | "imageBytesPptx"
    | "imagePptx"
    | "imageKeysPptx"
    | "copyPptx"
    | "exportPptxPdf" => self.pptx_operation(operation, request)
    "defaultPdfBudget"
    | "openPdf"
    | "queryPdf"
    | "renderPdfPage"
    | "extractPdfText"
    | "searchPdfPage"
    | "hitTestPdf"
    | "selectPdf"
    | "selectedPdfText"
    | "imagePdf"
    | "decodedImagePdf"
    | "reorderPdfPages"
    | "rotatePdfPages"
    | "deletePdfPages"
    | "addPdfNote"
    | "highlightPdfText"
    | "updatePdfAnnotation"
    | "deletePdfAnnotation"
    | "setPdfFieldValue"
    | "undoPdf"
    | "redoPdf"
    | "savePdf" => self.pdf_operation(operation, request)
    "query"
    | "editState"
    | "selectDocx"
    | "queryFormatting"
    | "docxThemeColors"
    | "docxThemeFonts"
    | "setDocxThemeFonts"
    | "setDocxThemeColor"
    | "runningArea"
    | "setRunningOptions"
    | "unlinkRunningArea"
    | "setRunningArea"
    | "pageSetup"
    | "setPageSetup"
    | "setPageBackground"
    | "setPageBorders"
    | "insertDocxTable"
    | "editDocxTable"
    | "styleCatalog"
    | "listCatalog"
    | "editList"
    | "updateListLevel"
    | "updateStyle"
    | "createStyle"
    | "deleteStyle"
    | "captureFormat"
    | "applyFormat"
    | "setCharacterFormat"
    | "setHyperlink"
    | "editBookmark"
    | "setParagraphFormat"
    | "setDefaultTabStop"
    | "findDocx"
    | "docxOverview"
    | "docxComments"
    | "navigateComment"
    | "editDocxComment"
    | "replaceDocxMatches"
    | "tabDocx"
    | "enterDocx"
    | "selectedText"
    | "beginComposition"
    | "updateComposition"
    | "commitComposition"
    | "cancelComposition"
    | "replaceRange"
    | "deleteDocx"
    | "undoDocx"
    | "redoDocx"
    | "replaceNode"
    | "saveDocx"
    | "flow"
    | "layout"
    | "hitTest"
    | "caret"
    | "selectionGeometry"
    | "navigateDocx"
    | "exportPdf"
    | "imageBytes"
    | "image" => {
      guard self.docx is Some(session) else {
        @failure.reject("invalid-operation", "Open a DOCX session first")
      }
      match operation {
        "query" => session.query()
        "editState" => session.edit_state()
        "enterDocx" => {
          let result = session.enter(field_int(request, "revision"))
          self.layout = None
          result
        }
        "tabDocx" => {
          guard request is { "backward": True | False as backward, .. } else {
            @failure.reject("invalid-operation", "Invalid tab direction")
          }
          let revision = field_int(request, "revision")
          let result = session.tab(revision, backward is True)
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "docxOverview" => session.overview(field_int(request, "revision"))
        "docxComments" => session.comments(field_int(request, "revision"))
        "navigateComment" =>
          session.navigate_comment(
            field_int(request, "revision"),
            field_string(request, "direction"),
          )
        "findDocx" =>
          session.find(
            field_int(request, "revision"),
            field_string(request, "text"),
            find_options(request),
          )
        "replaceDocxMatches" => {
          let revision = field_int(request, "revision")
          let result = session.replace_matches(
            revision,
            replacement_matches(request),
            field_string(request, "text"),
          )
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "beginComposition"
        | "updateComposition"
        | "commitComposition"
        | "cancelComposition" => {
          let revision = field_int(request, "revision")
          let result = match operation {
            "beginComposition" => session.begin_composition(revision)
            "updateComposition" =>
              session.update_composition(
                revision,
                field_int(request, "compositionId"),
                field_string(request, "text"),
              )
            "commitComposition" =>
              session.commit_composition(
                revision,
                field_int(request, "compositionId"),
                field_string(request, "text"),
              )
            _ =>
              session.cancel_composition(
                revision,
                field_int(request, "compositionId"),
              )
          }
          self.layout = None
          result
        }
        "selectedText" =>
          Json(
            session.selected_text(
              field_int(request, "revision"),
              field_selection(request),
              cut=xlsx_boolean(request, "cut"),
            ),
          )
        "selectDocx" =>
          session.select(
            field_int(request, "revision"),
            field_selection(request),
          )
        "queryFormatting" =>
          session.query_formatting(
            field_int(request, "revision"),
            field_selection(request),
          )
        "styleCatalog" =>
          session.style_catalog(
            field_int(request, "revision"),
            field_string(request, "kind"),
          )
        "docxThemeColors" =>
          session.theme_colors(field_int(request, "revision"))
        "docxThemeFonts" => session.theme_fonts(field_int(request, "revision"))
        "setDocxThemeFonts" => self.docx_theme_fonts(session, request)
        "setDocxThemeColor" => {
          let revision = field_int(request, "revision")
          let result = session.set_theme_color(
            revision,
            field_string(request, "slot"),
            field_string(request, "color"),
          )
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "setRunningOptions"
        | "unlinkRunningArea"
        | "runningArea"
        | "setRunningArea"
        | "pageSetup"
        | "setPageBackground"
        | "setPageBorders"
        | "setPageSetup" => self.docx_page(session, operation, request)
        "insertDocxTable" | "editDocxTable" =>
          self.docx_table(session, operation, request)
        "listCatalog" => session.list_catalog(field_int(request, "revision"))
        "updateListLevel" => {
          let result = session.update_list_level(
            field_int(request, "revision"),
            field_int(request, "listId"),
            field_int(request, "level"),
            list_level_format(request),
          )
          self.layout = None
          result
        }
        "editList" => {
          let result = session.edit_list(
            field_int(request, "revision"),
            field_selection(request),
            list_edit(request),
          )
          self.layout = None
          result
        }
        "setDefaultTabStop" => {
          let interval = match request {
            { "interval": Null, .. } => None
            { "interval": Number(value, ..), .. } => Some(value)
            _ =>
              @failure.reject(
                "invalid-operation", "Invalid default tab interval",
              )
          }
          let result = session.set_default_tab_stop(
            field_int(request, "revision"),
            interval,
          )
          self.layout = None
          result
        }
        "createStyle" | "deleteStyle" => {
          let revision = field_int(request, "revision")
          let result = if operation == "createStyle" {
            session.create_style(
              revision,
              field_string(request, "name"),
              field_string(request, "kind"),
              based_on=match request {
                { "basedOn": String(base), .. } => Some(base)
                Object(fields) if !fields.contains("basedOn") => None
                _ => @failure.reject("invalid-operation", "Invalid base style")
              },
            )
          } else {
            session.delete_style(
              revision,
              field_string(request, "key"),
              field_string(request, "replacement"),
            )
          }
          self.layout = None
          result
        }
        "captureFormat" =>
          session.capture_format(
            field_int(request, "revision"),
            field_selection(request),
          )
        "applyFormat" | "updateStyle" => {
          guard request is { "format": Object(fields) as format, .. } &&
            fields
            .keys()
            .all(key => {
              (if operation == "updateStyle" {
                ["character", "paragraph", "name", "basedOn", "reset"]
              } else {
                ["character", "paragraph"]
              }).contains(key)
            }) &&
            format is { "character": character, "paragraph": paragraph, .. } else {
            @failure.reject("invalid-operation", "Invalid copied format")
          }
          let revision = field_int(request, "revision")
          let result = if operation == "updateStyle" {
            let name = match fields.get("name") {
              Some(String(name)) => Some(name)
              None => None
              _ => @failure.reject("invalid-operation", "Invalid style name")
            }
            session.update_style(
              revision,
              field_string(request, "key"),
              character_format({ "format": character }),
              paragraph_format({ "format": paragraph }),
              name~,
              based_on=format_string(fields, "basedOn"),
              reset=match fields.get("reset") {
                None => false
                Some(True) => true
                _ =>
                  @failure.reject(
                    "invalid-operation", "Invalid style reset flag",
                  )
              },
            )
          } else {
            session.apply_format(
              revision,
              field_selection(request),
              character_format({ "format": character }),
              paragraph_format({ "format": paragraph }),
            )
          }
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "setCharacterFormat"
        | "setParagraphFormat"
        | "setHyperlink"
        | "editBookmark"
        | "editDocxComment" => {
          let revision = field_int(request, "revision")
          let result = edit_docx_format(session, request, operation, revision)
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "replaceRange" | "deleteDocx" | "undoDocx" | "redoDocx" => {
          let revision = field_int(request, "revision")
          let result = match operation {
            "replaceRange" =>
              session.replace_range(
                revision,
                field_selection(request),
                field_string(request, "text"),
                input_group=if request is Object(fields) &&
                  fields.get("inputGroup") is Some(_) {
                  Some(field_int(request, "inputGroup"))
                } else {
                  None
                },
              )
            "undoDocx" => session.undo_edit(revision)
            "deleteDocx" =>
              session.delete(revision, field_string(request, "direction"))
            _ => session.redo_edit(revision)
          }
          if result is { "revision": Number(current, ..), .. } &&
            current != revision.to_double() {
            self.layout = None
          }
          result
        }
        "flow" => self.docx_flow(session)
        "hitTest" => {
          let layout = self.current_layout(request)
          guard request is { "x": Number(x, ..), "y": Number(y, ..), .. } else {
            @failure.reject("invalid-position", "Hit coordinates are required")
          }
          self.hit_result(
            session,
            layout.hit_test(field_int(request, "page"), x, y),
          )
        }
        "caret" => {
          let layout = self.current_layout(request)
          guard request is { "position": position, .. } else {
            @failure.reject("invalid-position", "Caret position is required")
          }
          let position = field_position(position)
          session.check_position(position)
          self.hit_result(
            session,
            layout.caret(
              position.paragraph,
              position.offset,
              position.affinity,
              bidi_level?=position.bidiLevel,
              frame_start?=position.frameStart,
            ),
          )
        }
        "navigateDocx" => {
          let layout = self.current_layout(request)
          guard request is { "extend": True | False as extend_flag, .. } else {
            @failure.reject(
              "invalid-operation", "Navigation requires an extend flag",
            )
          }
          let hit = session.navigate(
            field_int(request, "revision"),
            layout,
            self.layout_id,
            field_string(request, "direction"),
            extend_selection=extend_flag is True,
          )
          {
            "state": session.edit_state(),
            "caret": self.hit_result(session, hit),
          }
        }
        "selectionGeometry" => {
          let layout = self.current_layout(request)
          let selection = field_selection(request)
          session.check_position(selection.anchor)
          session.check_position(selection.focus)
          let anchor = selection.anchor
          let focus = selection.focus
          {
            "layoutId": self.layout_id,
            "revision": layout.revision,
            "rects": layout.selection_rects(
              (anchor.paragraph, anchor.offset, anchor.affinity),
              (focus.paragraph, focus.offset, focus.affinity),
            ),
          }
        }
        "imageBytes" =>
          {
            "bytes": @base64.encode(
              session.image_bytes(field_string(request, "key")),
            ),
          }
        "image" => {
          self.images.add(
            field_string(request, "key"),
            field_int(request, "width"),
            field_int(request, "height"),
            input_bytes(request, 16777216),
          )
          self.layout = None
          { "key": self.images.get(field_string(request, "key")).identity }
        }
        "layout" => {
          guard request is { "profile": Object(fields), .. } &&
            fields.length() <= 64 else {
            @failure.reject(
              "invalid-operation", "Explicit font profile is required",
            )
          }
          let profile : Map[String, String] = Map([])
          for key, value in fields {
            guard value is String(identity) else {
              @failure.reject(
                "invalid-operation", "Invalid font profile identity",
              )
            }
            profile[key] = identity
          }
          self.layout = None
          let result = @layout.paginate(
            self.probe,
            session.flow(),
            profile,
            self.images,
          )
          self.layout = Some(result)
          self.layout_id += 1
          {
            "id": self.layout_id,
            "revision": result.revision,
            "shapedParagraphs": result.shapedParagraphs,
            "reusedParagraphs": result.reusedParagraphs,
            "reflowedPages": result.reflowedPages,
            "reusedPages": result.reusedPages,
            "profile": result.profile,
            "regions": result.drawing(self.images),
            "images": result.drawing_images(self.images),
            "semantics": result.semantics(),
            "comments": session.comment_overlays(result),
            "diagnostics": result.diagnostics,
            "outlines": result.outlines,
            "fonts": result.fonts,
          }
        }
        "exportPdf" => {
          session.check_idle()
          if request is Object(fields) && fields.get("layoutId") is Some(_) {
            guard field_int(request, "layoutId") == self.layout_id else {
              @failure.reject(
                "stale-layout", "PDF export requires the displayed layout",
              )
            }
          }
          guard self.layout is Some(layout) else {
            @failure.reject(
              "layout-required", "Create a current layout before PDF export",
            )
          }
          {
            "bytes": @base64.encode(
              @pdf.write(
                layout.positioned(),
                self.probe,
                self.images,
                field_int(request, "outputBytes"),
              ),
            ),
          }
        }
        "replaceNode" => {
          let previous = field_int(request, "revision")
          let revision = session.replace(
            field_int(request, "node"),
            previous,
            field_string(request, "text"),
          )
          if previous != revision {
            self.layout = None
          }
          { "revision": revision }
        }
        _ => { "bytes": @base64.encode(session.save()) }
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown foundation operation")
  }
}

///|
fn foundation_response(operation : () -> Json raise @failure.Failure) -> String {
  let result : Json = { "ok": true, "value": operation() } catch {
    @failure.Failure(code~, part~, offset~, message~) =>
      {
        "ok": false,
        "error": {
          "code": code,
          "part": part,
          "offset": offset,
          "message": message,
        },
      }
  }
  result.stringify()
}

///|
pub fn foundation_call(context : Foundation, input : String) -> String {
  foundation_response(() => {
    guard input.length() <= 100000000 else {
      @failure.reject("limit-exceeded", "ABI input exceeds budget")
    }
    let request = @json.parse(input) catch {
      _ => @failure.reject("invalid-operation", "Invalid request JSON")
    }
    context.dispatch(request)
  })
}

///|
pub fn foundation_close(context : Foundation) -> Unit {
  context.closed = true
  context.probe.close()
  if context.docx is Some(session) {
    session.close()
  }
  context.docx = None
  if context.xlsx is Some(session) {
    session.close()
  }
  context.xlsx = None
  if context.pptx is Some(session) {
    session.close()
  }
  context.pptx = None
  if context.pdf is Some(session) {
    session.close()
  }
  context.pdf = None
  context.layout = None
  context.xlsx_print = None
  context.images.clear()
}
