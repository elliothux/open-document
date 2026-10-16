///|
fn Foundation::xlsx_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "openXlsx" || operation == "createXlsx" {
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
      @xlsx.Session::create(budget)
    } else {
      @xlsx.Session::open(
        input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
        budget,
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
    "captureXlsxFormat" =>
      session.capture_format(field_int(request, "revision"))
    "applyXlsxFormat" => {
      guard request is { "format": format, .. } else {
        @failure.reject("invalid-operation", "Copied cell format is required")
      }
      session.apply_format(
        field_int(request, "revision"),
        xlsx_format_pattern(format),
      )
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
      let change = match field_string(change, "action") {
        "add" => @xlsx.Add
        "copy" => @xlsx.Copy
        "delete" => @xlsx.Delete
        "move" => @xlsx.Move(field_int(change, "index"))
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
      )
    }
    "undoXlsx" | "redoXlsx" =>
      session.undo(field_int(request, "revision"), redo=operation == "redoXlsx")
    "saveXlsx" => { "bytes": @base64.encode(session.save()) }
    "selectionXlsx" =>
      session.selection_geometry(field_int(request, "layoutId"))
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
    "pasteXlsx" =>
      session.paste(
        field_int(request, "revision"),
        field_string(request, "text"),
      )
    "clearXlsx" => session.clear(field_int(request, "revision"))
    "printXlsx" => {
      let revision = field_int(request, "revision")
      let document = session.print_layout(
        revision,
        field_string(request, "sheet"),
        if request is Object(fields) && fields.contains("range") {
          Some(field_string(request, "range"))
        } else {
          None
        },
        {
          width: xlsx_number(request, "width"),
          height: xlsx_number(request, "height"),
          left: xlsx_number(request, "left"),
          right: xlsx_number(request, "right"),
          top: xlsx_number(request, "top"),
          bottom: xlsx_number(request, "bottom"),
        },
        self.probe,
        xlsx_profile(request),
      )
      guard self.layout_id < 2147483647 else {
        @failure.reject("limit-exceeded", "Print identity exhausted")
      }
      self.layout_id += 1
      self.xlsx_print = Some((document, revision, self.layout_id))
      {
        "id": self.layout_id,
        "revision": revision,
        "sheet": field_string(request, "sheet"),
        "regions": document.drawing(self.images),
        "images": [],
        "outlines": self.probe.outline_resources(),
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
