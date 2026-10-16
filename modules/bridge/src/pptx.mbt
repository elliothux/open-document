///|
fn pptx_objects(request : Json) -> Array[String] raise @failure.Failure {
  guard request is Object(fields) &&
    fields.get("objects") is Some(Array(values)) &&
    values.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "A bounded object selection is required",
    )
  }
  values.map(value => {
    guard value is String(id) && id.length() <= 1024 else {
      @failure.reject("invalid-object", "Invalid selected object identity")
    }
    id
  })
}

///|
fn Foundation::pptx_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "openPptx" || operation == "createPptx" {
    guard self.docx is None &&
      self.xlsx is None &&
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
    let session = if operation == "createPptx" {
      @pptx.Session::create(budget)
    } else {
      @pptx.Session::open(
        input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
        budget,
      )
    }
    let result = session.query()
    self.pptx = Some(session)
    return result
  }
  guard self.pptx is Some(session) else {
    @failure.reject("session-required", "Open a PPTX presentation first")
  }
  match operation {
    "queryPptx" => session.query()
    "findPptx" | "replacePptxMatches" =>
      self.pptx_search(session, operation, request)
    "editPptxSlides" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Slide edit is required")
      }
      let change = match field_string(change, "action") {
        "add" => @pptx.AddSlide
        "copy" => @pptx.CopySlide
        "delete" => @pptx.DeleteSlide
        "move" => @pptx.MoveSlide(field_int(change, "index"))
        "hidden" => @pptx.HideSlide(xlsx_boolean(change, "hidden"))
        "size" =>
          @pptx.Size(
            xlsx_number(change, "width"),
            xlsx_number(change, "height"),
          )
        "background" => {
          let value = match change {
            { "value": Null, .. } => None
            { "value": String(value), .. } => Some(value)
            _ =>
              @failure.reject(
                "invalid-operation", "Slide background requires a color or null",
              )
          }
          @pptx.Background(value)
        }
        _ => @failure.reject("invalid-operation", "Unknown slide edit")
      }
      session.edit_slides(
        field_int(request, "revision"),
        field_string(request, "slide"),
        change,
      )
    }
    "editPptxObjects" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Object edit is required")
      }
      let change = match field_string(change, "action") {
        "imageOpacity" => @pptx.ImageOpacity(xlsx_number(change, "opacity"))
        "replaceImage" =>
          @pptx.ReplaceImage(
            field_string(change, "object"),
            input_bytes(change, 4194304),
          )
        "imageCrop" =>
          @pptx.ImageCrop(
            xlsx_number(change, "left"),
            xlsx_number(change, "top"),
            xlsx_number(change, "right"),
            xlsx_number(change, "bottom"),
          )
        "insertImage" =>
          @pptx.InsertImage(
            input_bytes(change, 4194304),
            xlsx_number(change, "x"),
            xlsx_number(change, "y"),
            xlsx_number(change, "width"),
            xlsx_number(change, "height"),
          )
        "insert" =>
          @pptx.Insert(
            field_string(change, "kind"),
            xlsx_number(change, "x"),
            xlsx_number(change, "y"),
            xlsx_number(change, "width"),
            xlsx_number(change, "height"),
            field_string(change, "text"),
          )
        "delete" => @pptx.Remove
        "clearTextFormat" => @pptx.ClearTextFormat
        "clearParagraphFormat" => @pptx.ClearParagraphFormat
        "textFormat" => {
          guard change is { "format": format, .. } else {
            @failure.reject("invalid-operation", "Text format is required")
          }
          @pptx.TextFormat(pptx_text_format(format))
        }
        "textAlign" => @pptx.TextAlign(field_string(change, "alignment"))
        "textParagraph" => {
          guard change is { "format": format, .. } else {
            @failure.reject("invalid-operation", "Paragraph format is required")
          }
          @pptx.TextParagraph(pptx_paragraph_format(format))
        }
        "textInsets" =>
          @pptx.TextInsets(
            xlsx_number(change, "left"),
            xlsx_number(change, "top"),
            xlsx_number(change, "right"),
            xlsx_number(change, "bottom"),
          )
        "textAnchor" => @pptx.TextAnchor(field_string(change, "anchor"))
        "textWrap" => @pptx.TextWrap(xlsx_boolean(change, "wrap"))
        "textFit" => @pptx.TextFit(field_string(change, "fit"))
        "strokeDash" =>
          @pptx.StrokeDash(
            match change {
              { "dash": Null, .. } => None
              { "dash": String(value), .. } => Some(value)
              _ =>
                @failure.reject("invalid-operation", "Border dash is required")
            },
          )
        "fill" | "stroke" => {
          let color = match change {
            { "color": Null, .. } => None
            { "color": String(color), .. } => Some(color)
            _ => @failure.reject("invalid-operation", "Shape color is required")
          }
          if field_string(change, "action") == "fill" {
            @pptx.Fill(color)
          } else {
            @pptx.Stroke(color, xlsx_number(change, "width"))
          }
        }
        "group" => @pptx.Group
        "ungroup" => @pptx.Ungroup
        "duplicate" =>
          @pptx.Duplicate(xlsx_number(change, "dx"), xlsx_number(change, "dy"))
        "rotate" => @pptx.Rotate(xlsx_number(change, "angle"))
        "flip" =>
          match field_string(change, "axis") {
            "horizontal" => @pptx.Flip(true)
            "vertical" => @pptx.Flip(false)
            _ => @failure.reject("invalid-operation", "Unknown flip axis")
          }
        "layer" => @pptx.Layer(field_string(change, "order"))
        "align" =>
          @pptx.Align(
            field_string(change, "alignment"),
            field_string(change, "relativeTo"),
          )
        "distribute" =>
          @pptx.Distribute(
            field_string(change, "axis"),
            field_string(change, "relativeTo"),
          )
        _ => @failure.reject("invalid-operation", "Unknown object edit")
      }
      session.edit_objects(
        field_int(request, "revision"),
        change,
        self.probe,
        xlsx_profile(request),
      )
    }
    "selectPptx" =>
      session.select(
        field_int(request, "revision"),
        field_string(request, "slide"),
        field_string(request, "object"),
        field_string(request, "mode"),
        field_int(request, "anchor"),
        field_int(request, "focus"),
        objects=Some(pptx_objects(request)),
      )
    "replacePptx" =>
      session.replace(
        field_int(request, "revision"),
        field_string(request, "text"),
        self.probe,
        xlsx_profile(request),
        candidate_id=if request is Object(fields) &&
          fields.contains("candidateId") {
          Some(field_int(request, "candidateId"))
        } else {
          None
        },
      )
    "deletePptx" =>
      session.delete(
        field_int(request, "revision"),
        xlsx_boolean(request, "backward"),
        self.probe,
        xlsx_profile(request),
      )
    "undoPptx" | "redoPptx" =>
      session.undo(field_int(request, "revision"), redo=operation == "redoPptx")
    "savePptx" =>
      { "bytes": @base64.encode(session.save(field_int(request, "revision"))) }
    "layoutPptx" =>
      session.layout(self.probe, xlsx_profile(request), self.images)
    "hitPptx" =>
      session.hit(
        field_int(request, "layoutId"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
        xlsx_number(request, "tolerance"),
      )
    "selectionPptx" =>
      session.selection_geometry(field_int(request, "layoutId"))
    "navigatePptx" =>
      session.navigate(
        field_int(request, "revision"),
        field_int(request, "layoutId"),
        field_string(request, "direction"),
        xlsx_boolean(request, "extend"),
      )
    "beginPptx" =>
      session.begin(
        field_int(request, "revision"),
        field_string(request, "kind"),
      )
    "transformPptx" =>
      session.transform(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
        xlsx_number(request, "width"),
        xlsx_number(request, "height"),
      )
    "dragPptx" =>
      session.drag(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        xlsx_number(request, "dx"),
        xlsx_number(request, "dy"),
        field_int(request, "handle"),
      )
    "finishPptx" =>
      session.finish(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        self.probe,
        xlsx_profile(request),
      )
    "cancelPptx" =>
      session.cancel(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
      )
    "copyPptx" => { "text": session.copy(field_int(request, "revision")) }
    "imageBytesPptx" =>
      {
        "bytes": @base64.encode(
          session.image_bytes(field_string(request, "key")),
        ),
      }
    "imagePptx" => {
      let key = field_string(request, "key")
      ignore(session.image_bytes(key))
      self.images.add(
        key,
        field_int(request, "width"),
        field_int(request, "height"),
        input_bytes(request, 16777216),
      )
      session.invalidate_geometry()
      { "key": self.images.get(key).identity }
    }
    "imageKeysPptx" => {
      let keys = session.image_keys(
        xlsx_boolean(request, "all"),
        xlsx_boolean(request, "hidden"),
      )
      self.images.retain(keys)
      Json(keys)
    }
    "exportPptxPdf" => {
      let document = session.print_layout(
        field_int(request, "revision"),
        xlsx_boolean(request, "all"),
        xlsx_boolean(request, "hidden"),
        self.probe,
        xlsx_profile(request),
      )
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
    _ => @failure.reject("invalid-operation", "Unknown PPTX operation")
  }
}
