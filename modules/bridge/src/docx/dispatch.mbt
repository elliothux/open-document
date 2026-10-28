///|
fn Context::dispatch(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Context session is closed")
  }
  let operation = field_string(request, "operation")
  if self.docx is Some(session) &&
    request is { "trackingDate": String(date), .. } {
    session.tracking_clock(date)
  }
  if is_docx_note_operation(operation) {
    return self.docx_note_operation(operation, request)
  }
  match operation {
    "docxMathFractions"
    | "editDocxMathFraction"
    | "docxMathScripts"
    | "docxMathExpressions"
    | "editDocxMath"
    | "editDocxMathScript" => self.math_operation(operation, request)
    "docxCharts" | "editDocxChart" => self.chart_operation(operation, request)
    "docxShapes" | "editDocxShape" => self.shape_operation(operation, request)
    "docxInk" => self.ink_operation(request)
    "docxPictures" | "editDocxPicture" | "docxDrawingGesture" =>
      self.picture_operation(operation, request)
    "budget" => archive_budget()
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
      guard self.docx is None else {
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
        @model.Session::create(budget)
      } else {
        @model.Session::open(
          input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
          budget,
        )
      }
      self.docx = Some(session)
      session.query()
    }
    "query"
    | "editState"
    | "selectDocx"
    | "selectAllDocx"
    | "queryFormatting"
    | "docxRuler"
    | "editDocxRuler"
    | "docxThemeColors"
    | "docxThemeFonts"
    | "setDocxThemeFonts"
    | "setDocxThemeColor"
    | "runningArea"
    | "setRunningOptions"
    | "setRunningLink"
    | "setRunningArea"
    | "pageSetup"
    | "documentProtection"
    | "setDocumentProtection"
    | "setPageColumns"
    | "setCoverPage"
    | "setPageSetup"
    | "setPageNumbering"
    | "updateBodyPageFields"
    | "insertBodyPageField"
    | "insertSectionBreak"
    | "insertDocxCaption"
    | "docxTableOfContents"
    | "docxSources"
    | "editDocxSource"
    | "editDocxCitation"
    | "editDocxBibliography"
    | "docxIndexes"
    | "editDocxIndex"
    | "editDocxTableOfContents"
    | "bodyPageField"
    | "editBodyPageField"
    | "setPageBackground"
    | "watermark"
    | "setWatermark"
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
    | "docxRevisions"
    | "docxTracking"
    | "setDocxTracking"
    | "docxRevisionGeometry"
    | "resolveDocxRevisions"
    | "navigateComment"
    | "editDocxComment"
    | "replaceDocxMatches"
    | "tabDocx"
    | "enterDocx"
    | "selectedText"
    | "docxClipboard"
    | "bodyFragmentImages"
    | "pasteBodyFragment"
    | "pasteMarkdown"
    | "pasteHtml"
    | "markupImages"
    | "tableClipboard"
    | "tableFragmentImages"
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
    | "exportDocxMarkup"
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
        "exportDocxMarkup" =>
          {
            "bytes": @base64.encode(
              session.export_markup(
                field_int(request, "revision"),
                field_string(request, "format"),
                field_int(request, "outputBytes"),
                layout?=self.layout,
              ),
            ),
          }
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
        "docxRevisions"
        | "resolveDocxRevisions"
        | "docxRevisionGeometry"
        | "docxTracking"
        | "setDocxTracking" => self.docx_revisions(session, request, operation)
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
        "selectedText"
        | "tableClipboard"
        | "tableFragmentImages"
        | "docxClipboard"
        | "bodyFragmentImages"
        | "pasteBodyFragment"
        | "pasteMarkdown"
        | "pasteHtml"
        | "markupImages" => self.clipboard_command(session, request)
        "selectDocx" | "selectAllDocx" =>
          select_docx(session, request, operation == "selectAllDocx")
        "queryFormatting" =>
          session.query_formatting(
            field_int(request, "revision"),
            field_selection(request),
            layout?=self.layout,
          )
        "docxRuler" | "editDocxRuler" =>
          self.docx_ruler(session, request, operation == "editDocxRuler")
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
        | "setRunningLink"
        | "runningArea"
        | "setRunningArea"
        | "pageSetup"
        | "documentProtection"
        | "setDocumentProtection"
        | "setPageColumns"
        | "setCoverPage"
        | "setPageBackground"
        | "watermark"
        | "setWatermark"
        | "setPageBorders"
        | "setPageNumbering"
        | "updateBodyPageFields"
        | "insertBodyPageField"
        | "insertSectionBreak"
        | "insertDocxCaption"
        | "docxTableOfContents"
        | "docxSources"
        | "editDocxSource"
        | "editDocxCitation"
        | "editDocxBibliography"
        | "docxIndexes"
        | "editDocxIndex"
        | "editDocxTableOfContents"
        | "bodyPageField"
        | "editBodyPageField"
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
        "applyFormat" | "updateStyle" =>
          self.edit_docx_style(session, request, operation)
        "setCharacterFormat"
        | "setParagraphFormat"
        | "setHyperlink"
        | "editBookmark"
        | "editDocxComment" => {
          let revision = field_int(request, "revision")
          let result = edit_docx_format(
            session,
            request,
            operation,
            revision,
            self.probe,
            self.images,
          )
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
          {
            "layoutId": self.layout_id,
            "revision": layout.revision,
            "rects": session.selection_rects(layout, selection),
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
          let positioned = session.page_positioned(result, self.probe)
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
            "regions": positioned.drawing(self.images),
            "images": positioned.drawing_images(self.images),
            "semantics": result.semantics(),
            "comments": session.comment_overlays(result),
            "diagnostics": result.diagnostics,
            "outlines": self.probe.outline_resources(),
            "fonts": positioned.fonts,
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
                {
                  ..session.page_positioned(layout, self.probe),
                  links: session.page_links(layout),
                },
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
