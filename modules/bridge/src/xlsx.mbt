///|
fn Foundation::xlsx_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "openXlsx" ||
    operation == "createXlsx" ||
    operation == "importXlsxDelimited" {
    guard self.xlsx is None &&
      self.docx is None &&
      self.pptx is None &&
      self.pdf is None else {
      @failure.reject("invalid-operation", "A document session is already open")
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
    let session = if operation == "createXlsx" {
      @xlsx.Session::create(budget, date=xlsx_calendar_date(request))
    } else if operation == "importXlsxDelimited" {
      guard request is { "options": options, .. } else {
        @failure.reject("invalid-operation", "Import options are required")
      }
      @xlsx.Session::import_delimited(
        input_bytes(
          request,
          budget.file_bytes.min(budget.retained_bytes).min(4194304),
        ),
        field_string(request, "delimiter"),
        budget,
        numbers=xlsx_boolean(options, "numbers"),
        dates=xlsx_boolean(options, "dates"),
        formulas=xlsx_boolean(options, "formulas"),
        date=xlsx_calendar_date(request),
      )
    } else {
      @xlsx.Session::open(
        input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
        budget,
        date=xlsx_calendar_date(request),
      )
    }
    let result = session.query()
    self.xlsx = Some(session)
    return result
  }
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  match operation {
    "pivotsXlsx" | "slicersXlsx" | "timelinesXlsx" | "pivotPreviewXlsx" =>
      xlsx_analysis_query(session, operation, request)
    "duplicatesXlsx" | "textColumnsXlsx" =>
      xlsx_data(session, operation, request)
    "exportXlsxCsv" =>
      {
        "bytes": @base64.encode(
          session.export_csv(
            field_int(request, "revision"),
            selection=xlsx_boolean(request, "selection"),
          ),
        ),
      }
    "findXlsx" | "replaceXlsxMatches" => {
      guard request is { "options": options, .. } else {
        @failure.reject("invalid-operation", "Search options are required")
      }
      let options = @xlsx.FindOptions::new(
        matchCase=xlsx_boolean(options, "matchCase"),
        wholeCell=xlsx_boolean(options, "wholeCell"),
        formulas=xlsx_boolean(options, "formulas"),
        workbook=xlsx_boolean(options, "workbook"),
      )
      let revision = field_int(request, "revision")
      let sheet = field_string(request, "sheet")
      let text = field_string(request, "text")
      if operation == "findXlsx" {
        session.find(revision, sheet, text, options)
      } else {
        let index = match request {
          { "index": Null, .. } => None
          { "index": _, .. } => Some(field_int(request, "index"))
          _ => None
        }
        session.replace_matches(
          revision,
          sheet,
          text,
          options,
          field_string(request, "replacement"),
          index,
        )
      }
    }
    "autoFitXlsx" => {
      let axis = field_string(request, "axis")
      guard axis == "rows" || axis == "columns" else {
        @failure.reject("invalid-operation", "Invalid automatic fitting axis")
      }
      session.auto_fit(
        field_int(request, "revision"),
        field_string(request, "sheet"),
        field_int(request, "first"),
        field_int(request, "last"),
        self.probe,
        xlsx_profile(request),
        rows=axis == "rows",
      )
    }
    "captureXlsxFormat" =>
      session.capture_format(field_int(request, "revision"))
    "applyXlsxFormat" => {
      guard request is { "format": format, .. } else {
        @failure.reject("invalid-operation", "Copied cell format is required")
      }
      let (pattern, merges) = xlsx_copied_format(format)
      session.apply_format(field_int(request, "revision"), pattern, merges)
    }
    "formatXlsxCells" => {
      guard request is { "patch": patch, .. } else {
        @failure.reject("invalid-operation", "Cell format patch is required")
      }
      session.format_cells(
        field_int(request, "revision"),
        xlsx_cell_format(patch),
      )
    }
    "editXlsxSheet" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Worksheet edit is required")
      }
      if [
          "createPivot", "refreshPivot", "updatePivot", "deletePivot", "filterSlicer",
          "selectSlicer", "scrollSlicer", "deleteSlicer", "filterTimeline", "deleteTimeline",
          "setTimelineLevel", "scrollTimeline", "setTimelineEndpoint",
        ].contains(field_string(change, "action")) {
        return xlsx_pivot_edit(
          session,
          field_int(request, "revision"),
          field_string(request, "sheet"),
          change,
        )
      }
      let change = match field_string(change, "action") {
        "protection" | "workbookProtection" => {
          guard change is Object(fields) &&
            fields
            .keys()
            .all(k => ["action", "enabled", "password"].contains(k)) else {
            @failure.reject(
              "invalid-operation", "Invalid worksheet protection fields",
            )
          }
          let salt = match request {
            { "passwordSalt": String(value), .. } => {
              guard value.length() <= 24 else {
                @failure.reject(
                  "invalid-operation", "Invalid worksheet password salt",
                )
              }
              @base64.decode(value[:]) catch {
                _ =>
                  @failure.reject(
                    "invalid-operation", "Invalid worksheet password salt",
                  )
              }
            }
            _ => b""
          }
          let password = match fields.get("password") {
            Some(String(value)) => value
            None => ""
            _ =>
              @failure.reject("invalid-operation", "Invalid worksheet password")
          }
          if field_string(change, "action") == "workbookProtection" {
            @xlsx.WorkbookProtection(
              xlsx_boolean(change, "enabled"),
              password,
              salt,
            )
          } else {
            @xlsx.Protection(xlsx_boolean(change, "enabled"), password, salt)
          }
        }
        "add" => @xlsx.Add
        "copy" => @xlsx.Copy
        "textToColumns" => {
          guard change is Object(fields) &&
            fields.length() == 4 &&
            fields
            .keys()
            .all(k => {
              ["action", "settings", "sourceRevision", "overwrite"].contains(k)
            }) &&
            fields.get("settings") is Some(settings) else {
            @failure.reject(
              "invalid-operation", "Invalid text to columns command",
            )
          }
          @xlsx.TextToColumns(
            xlsx_column_settings(settings),
            field_int(change, "sourceRevision"),
            xlsx_boolean(change, "overwrite"),
          )
        }
        "removeDuplicates" => {
          guard change is Object(fields) &&
            fields.length() == 3 &&
            fields
            .keys()
            .all(k => ["action", "settings", "sourceRevision"].contains(k)) &&
            fields.get("settings") is Some(settings) else {
            @failure.reject(
              "invalid-operation", "Invalid duplicate removal command",
            )
          }
          @xlsx.RemoveDuplicates(
            xlsx_duplicate_settings(settings),
            field_int(change, "sourceRevision"),
          )
        }
        "delete" => @xlsx.Delete
        "sparkline" => xlsx_sparkline_edit(change)
        "conditionalRule" => {
          guard change is { "priority": priority, "rule": rule, .. } else {
            @failure.reject(
              "invalid-operation", "Conditional rule settings are required",
            )
          }
          @xlsx.ConditionalRule(
            field_string(change, "ranges"),
            if priority is Null {
              None
            } else {
              Some(field_int(change, "priority"))
            },
            if rule is Null {
              None
            } else {
              Some(xlsx_conditional_settings(rule))
            },
            field_int(change, "sourceRevision"),
          )
        }
        "conditionalPriority" =>
          @xlsx.ConditionalPriority(
            field_int(change, "priority"),
            field_int(change, "position"),
            field_int(change, "sourceRevision"),
          )
        "drawingOrder" => xlsx_drawing_order(change)
        "duplicateDrawing" => xlsx_duplicate_drawing(change)
        "moveDrawing" => xlsx_move_drawing(change)
        "note" => {
          guard change is Object(fields) &&
            fields
            .keys()
            .all(k => ["action", "cell", "text", "author"].contains(k)) else {
            @failure.reject(
              "invalid-operation", "Invalid cell note command fields",
            )
          }
          let text = match fields.get("text") {
            Some(Null) => None
            Some(String(value)) => Some(value)
            _ =>
              @failure.reject(
                "invalid-operation", "Cell note text or null is required",
              )
          }
          let author = match fields.get("author") {
            None => ""
            Some(String(value)) => value
            _ =>
              @failure.reject("invalid-operation", "Invalid cell note author")
          }
          @xlsx.Note(field_string(change, "cell"), text, author)
        }
        "hyperlink" => {
          guard change is Object(fields) &&
            fields.length() == 3 &&
            fields.keys().all(k => ["action", "range", "target"].contains(k)) else {
            @failure.reject(
              "invalid-operation", "Invalid hyperlink command fields",
            )
          }
          @xlsx.Hyperlink(
            field_string(change, "range"),
            match fields.get("target") {
              Some(Null) => None
              Some(String(value)) => Some(value)
              _ =>
                @failure.reject("invalid-operation", "Invalid hyperlink target")
            },
          )
        }
        "openHyperlink" => {
          guard change is Object(fields) &&
            fields.length() == 3 &&
            fields
            .keys()
            .all(k => ["action", "range", "sourceRevision"].contains(k)) else {
            @failure.reject(
              "invalid-operation", "Invalid hyperlink navigation fields",
            )
          }
          @xlsx.OpenHyperlink(
            field_string(change, "range"),
            field_int(change, "sourceRevision"),
          )
        }
        "validation" => {
          guard change is { "rule": rule, .. } else {
            @failure.reject(
              "invalid-operation", "Data validation settings are required",
            )
          }
          @xlsx.Validation(
            field_string(change, "range"),
            if rule is Null {
              None
            } else {
              Some(xlsx_validation_settings(rule))
            },
          )
        }
        "validationValue" =>
          @xlsx.ValidationValue(
            field_int(change, "index"),
            field_int(change, "sourceRevision"),
          )
        "merge" =>
          @xlsx.Merge(
            field_string(change, "range"),
            xlsx_boolean(change, "discard"),
          )
        "unmerge" => @xlsx.Unmerge(field_string(change, "range"))
        "sort" => xlsx_sort(change)
        "filter" => xlsx_filter(change)
        "group"
        | "ungroup"
        | "collapseGroup"
        | "clearOutline"
        | "outlineSummary"
        | "renameTable"
        | "createTable"
        | "resizeTable"
        | "tableColumnFormula"
        | "tableTotals"
        | "tableStyle"
        | "tableStyleDefinition"
        | "deleteTableStyle"
        | "tableTotal"
        | "tableFilter"
        | "tableFilterClear"
        | "tableFilterRemove"
        | "tableFilterReapply"
        | "renameTableColumn" => xlsx_table_edit(change)
        "filterClear" => @xlsx.ClearFilter
        "filterRemove" => @xlsx.RemoveFilter
        "filterReapply" => @xlsx.ReapplyFilter
        "fill" =>
          @xlsx.Fill(
            field_string(change, "range"),
            field_string(change, "direction"),
          )
        "series" =>
          @xlsx.Series(
            match field_string(change, "mode") {
              "linear" => @xlsx.Linear
              "growth" => @xlsx.Growth
              "text" => @xlsx.TextSeries
              "auto" => @xlsx.Automatic
              "copy" => @xlsx.CopySeries
              "shrink" => @xlsx.Shrink
              "date" =>
                @xlsx.Date(
                  field_string(change, "unit"),
                  xlsx_number(change, "step"),
                )
              _ => @failure.reject("invalid-operation", "Invalid series mode")
            },
            field_string(change, "source"),
            field_string(change, "range"),
            field_string(change, "direction"),
          )
        "view" =>
          @xlsx.View({
            grid_lines: xlsx_boolean(change, "gridLines"),
            headings: xlsx_boolean(change, "headings"),
            rtl: xlsx_boolean(change, "rtl"),
            formulas: xlsx_boolean(change, "formulas"),
          })
        "name" =>
          @xlsx.SetName({
            original: xlsx_optional_string(change, "original"),
            name: field_string(change, "name"),
            scope: xlsx_optional_string(change, "scope"),
            formula: field_string(change, "formula"),
          })
        "nameDelete" =>
          @xlsx.DeleteName(
            field_string(change, "name"),
            xlsx_optional_string(change, "scope"),
          )
        "nameSelect" =>
          @xlsx.SelectName(
            field_string(change, "name"),
            xlsx_optional_string(change, "scope"),
          )
        "freeze" =>
          @xlsx.Freeze(field_int(change, "rows"), field_int(change, "columns"))
        "pageSetup" =>
          @xlsx.PageSetup({
            paper: field_string(change, "paper"),
            orientation: field_string(change, "orientation"),
            left: xlsx_number(change, "left"),
            top: xlsx_number(change, "top"),
            right: xlsx_number(change, "right"),
            bottom: xlsx_number(change, "bottom"),
            scale: field_int(change, "scale"),
            fitWidth: field_int(change, "fitWidth"),
            fitHeight: field_int(change, "fitHeight"),
          })
        "printRange" =>
          @xlsx.PrintRange({
            area: field_string(change, "area"),
            rows: field_string(change, "rows"),
            columns: field_string(change, "columns"),
          })
        "headerFooter" =>
          @xlsx.HeaderFooter({
            oddHeader: field_string(change, "oddHeader"),
            oddFooter: field_string(change, "oddFooter"),
            evenHeader: field_string(change, "evenHeader"),
            evenFooter: field_string(change, "evenFooter"),
            firstHeader: field_string(change, "firstHeader"),
            firstFooter: field_string(change, "firstFooter"),
            differentFirst: xlsx_boolean(change, "differentFirst"),
            differentOddEven: xlsx_boolean(change, "differentOddEven"),
            scaleWithDoc: xlsx_boolean(change, "scaleWithDoc"),
            alignWithMargins: xlsx_boolean(change, "alignWithMargins"),
            headerMargin: xlsx_number(change, "headerMargin"),
            footerMargin: xlsx_number(change, "footerMargin"),
          })
        "move" => @xlsx.Move(field_int(change, "index"))
        "insertRows" =>
          @xlsx.InsertRows(
            field_int(change, "first"),
            field_int(change, "count"),
          )
        "deleteRows" =>
          @xlsx.DeleteRows(
            field_int(change, "first"),
            field_int(change, "count"),
          )
        "insertColumns" =>
          @xlsx.InsertColumns(
            field_int(change, "first"),
            field_int(change, "count"),
          )
        "deleteColumns" =>
          @xlsx.DeleteColumns(
            field_int(change, "first"),
            field_int(change, "count"),
          )
        "insertCells" =>
          @xlsx.InsertCells(
            field_string(change, "range"),
            field_string(change, "direction"),
          )
        "deleteCells" =>
          @xlsx.DeleteCells(
            field_string(change, "range"),
            field_string(change, "direction"),
          )
        "moveCells" =>
          @xlsx.MoveCells(
            field_string(change, "sourceSheet"),
            field_string(change, "source"),
            field_string(change, "destination"),
          )
        "visibility" => @xlsx.Visibility(field_string(change, "state"))
        "rename" => @xlsx.Rename(field_string(change, "name"))
        "rowHeight" =>
          @xlsx.RowHeight(
            field_int(change, "first"),
            field_int(change, "last"),
            xlsx_number(change, "size"),
          )
        "columnWidth" =>
          @xlsx.ColumnWidth(
            field_int(change, "first"),
            field_int(change, "last"),
            xlsx_number(change, "size"),
          )
        _ => @failure.reject("invalid-operation", "Unknown worksheet edit")
      }
      session.edit_sheet(
        field_int(request, "revision"),
        field_string(request, "sheet"),
        change,
        date=xlsx_calendar_date(request),
      )
    }
    "queryXlsx" =>
      session.query(
        sheet=if request is Object(fields) && fields.contains("sheet") {
          Some(field_string(request, "sheet"))
        } else {
          None
        },
        range=if request is Object(fields) && fields.contains("range") {
          Some(field_string(request, "range"))
        } else {
          None
        },
      )
    "selectXlsx" =>
      session.select(
        field_int(request, "revision"),
        field_string(request, "sheet"),
        field_string(request, "range"),
      )
    "replaceXlsx" => {
      guard request is { "values": Array(rows), "literal": literal, .. } &&
        (literal == Json(true) || literal == Json(false)) &&
        rows.length() <= 4096 else {
        @failure.reject(
          "invalid-operation", "Explicit rectangular values are required",
        )
      }
      let mut cells = 0
      let values = rows.map(row => {
        guard row is Array(fields) else {
          @failure.reject("invalid-operation", "Expected value row")
        }
        cells += fields.length()
        guard cells <= 4096 else {
          @failure.reject("limit-exceeded", "Edit cell count exceeds budget")
        }
        fields.map(value => {
          guard value is String(text) else {
            @failure.reject("invalid-operation", "Expected cell input string")
          }
          text
        })
      })
      session.replace(
        field_int(request, "revision"),
        field_string(request, "sheet"),
        field_string(request, "range"),
        values,
        literal=literal == Json(true),
        accept_warnings=xlsx_boolean(request, "acceptWarnings"),
      )
    }
    "undoXlsx" | "redoXlsx" =>
      session.undo(field_int(request, "revision"), redo=operation == "redoXlsx")
    "saveXlsx" => { "bytes": @base64.encode(session.save()) }
    "selectionXlsx" =>
      session.selection_geometry(field_int(request, "layoutId"))
    "fillPreviewXlsx" => {
      guard request is { "target": target, .. } else {
        @failure.reject("invalid-operation", "Fill target is required")
      }
      session.fill_preview(
        field_int(request, "layoutId"),
        match field_string(target, "kind") {
          "point" =>
            @xlsx.FillPoint(xlsx_number(target, "x"), xlsx_number(target, "y"))
          "direction" => @xlsx.FillDirection(field_string(target, "direction"))
          "adjacent" => @xlsx.FillAdjacent
          _ => @failure.reject("invalid-operation", "Invalid fill target")
        },
        ctrl=if target is Object(fields) && fields.contains("ctrl") {
          xlsx_boolean(target, "ctrl")
        } else {
          false
        },
      )
    }
    "viewportXlsx" =>
      session.viewport(
        field_string(request, "sheet"),
        xlsx_number(request, "scrollX"),
        xlsx_number(request, "scrollY"),
        xlsx_number(request, "width"),
        xlsx_number(request, "height"),
        self.probe,
        xlsx_profile(request),
        reveal=xlsx_boolean(request, "reveal"),
        images=self.images,
      )
    "hitXlsx" =>
      {
        "address": session.hit(
          field_int(request, "layoutId"),
          xlsx_number(request, "x"),
          xlsx_number(request, "y"),
        ),
      }
    "navigateXlsx" =>
      session.navigate(
        field_int(request, "revision"),
        field_string(request, "direction"),
        xlsx_boolean(request, "extend"),
      )
    "copyXlsx" => { "text": session.copy(field_int(request, "revision")) }
    "captureXlsxCells" =>
      Json(session.capture_cells(field_int(request, "revision")))
    "pasteXlsxCells" => {
      guard request is { "copied": copied, .. } else {
        @failure.reject("invalid-operation", "Copied cells required")
      }
      session.paste_cells(
        field_int(request, "revision"),
        xlsx_copied_cells(copied),
        field_string(request, "mode"),
        transpose=xlsx_boolean(request, "transpose"),
        accept_warnings=xlsx_boolean(request, "acceptWarnings"),
      )
    }
    "pasteXlsx" =>
      session.paste(
        field_int(request, "revision"),
        field_string(request, "text"),
        accept_warnings=xlsx_boolean(request, "acceptWarnings"),
      )
    "clearXlsx" =>
      session.clear(
        field_int(request, "revision"),
        mode=field_string(request, "mode"),
      )
    "printXlsx" => {
      let revision = field_int(request, "revision")
      guard request is { "options": options, .. } else {
        @failure.reject("invalid-operation", "Print options are required")
      }
      guard options is Null || options is Object(_) else {
        @failure.reject(
          "invalid-operation", "Print options must be an object or null",
        )
      }
      let paper_keys = ["width", "height", "left", "right", "top", "bottom"]
      let setup : @layout.PageSetup? = if options is Object(fields) &&
        paper_keys.any(key => fields.contains(key)) {
        guard paper_keys.all(key => fields.contains(key)) else {
          @failure.reject(
            "invalid-operation", "All six temporary paper fields are required together",
          )
        }
        Some({
          width: xlsx_number(options, "width"),
          height: xlsx_number(options, "height"),
          left: xlsx_number(options, "left"),
          right: xlsx_number(options, "right"),
          top: xlsx_number(options, "top"),
          bottom: xlsx_number(options, "bottom"),
        })
      } else {
        None
      }
      let sheets = match options {
        { "sheets": String("visible"), .. } => @xlsx.VisibleSheets
        { "sheets": Array(ids), .. } =>
          @xlsx.SelectedSheets(
            ids.map(value => {
              match value {
                String(id) => id
                _ =>
                  @failure.reject(
                    "invalid-sheet", "Printed worksheet identities must be strings",
                  )
              }
            }),
          )
        Object(fields) if fields.contains("sheets") =>
          @failure.reject(
            "invalid-sheet", "Unknown printed worksheet selection",
          )
        _ => @xlsx.CurrentSheet
      }
      let document = session.print_layout(
        revision,
        field_string(request, "sheet"),
        if options is Object(fields) && fields.contains("range") {
          Some(field_string(options, "range"))
        } else {
          None
        },
        self.probe,
        xlsx_profile(request),
        setup?,
        sheets~,
      )
      let regions = document.drawing(self.images)
      let outlines = self.probe.outline_resources()
      guard self.layout_id < 2147483647 else {
        @failure.reject("limit-exceeded", "Print identity exhausted")
      }
      self.layout_id += 1
      self.xlsx_print = Some((document, revision, self.layout_id))
      {
        "id": self.layout_id,
        "revision": revision,
        "sheet": field_string(request, "sheet"),
        "regions": regions,
        "images": document.drawing_images(self.images),
        "outlines": outlines,
      }
    }
    "exportXlsxPdf" => {
      guard self.xlsx_print is Some((document, revision, id)) &&
        id == field_int(request, "layoutId") &&
        revision == field_int(session.query(), "revision") else {
        @failure.reject(
          "stale-layout", "Create a current print layout before PDF export",
        )
      }
      {
        "bytes": @base64.encode(
          @pdf.write(
            document,
            self.probe,
            self.images,
            field_int(request, "outputBytes"),
          ),
        ),
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown XLSX operation")
  }
}

///|
fn xlsx_number(request : Json, field : String) -> Double raise @failure.Failure {
  guard request is Object(fields) &&
    fields.get(field) is Some(Number(value, ..)) &&
    !value.is_nan() &&
    !value.is_inf() else {
    @failure.reject("invalid-operation", "Invalid numeric field: " + field)
  }
  value
}

///|
fn xlsx_boolean(request : Json, field : String) -> Bool raise @failure.Failure {
  guard request is Object(fields) else {
    @failure.reject("invalid-operation", "Expected request object")
  }
  match fields.get(field) {
    Some(True) => true
    Some(False) => false
    _ => @failure.reject("invalid-operation", "Invalid boolean field: " + field)
  }
}

///|
fn xlsx_profile(request : Json) -> Map[String, String] raise @failure.Failure {
  guard request is { "profile": Object(fields), .. } && fields.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "Explicit bounded font profile is required",
    )
  }
  let profile : Map[String, String] = Map([])
  for key, value in fields {
    guard value is String(identity) &&
      key.length() <= 256 &&
      identity.length() <= 256 else {
      @failure.reject("invalid-operation", "Invalid font profile")
    }
    profile[key] = identity
  }
  profile
}
