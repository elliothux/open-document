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
    let date_time = match request {
      { "dateTime": String(value), .. } => Some(value)
      { "dateTime": _, .. } =>
        @failure.reject(
          "invalid-operation", "Invalid presentation date and time",
        )
      _ => None
    }
    let session = if operation == "createPptx" {
      match date_time {
        Some(value) => @pptx.Session::create(budget, date_time=value)
        None => @pptx.Session::create(budget)
      }
    } else {
      let bytes = input_bytes(
        request,
        budget.file_bytes.min(budget.retained_bytes),
      )
      match date_time {
        Some(value) => @pptx.Session::open(bytes, budget, date_time=value)
        None => @pptx.Session::open(bytes, budget)
      }
    }
    let result = session.query()
    self.pptx = Some(session)
    return result
  }
  guard self.pptx is Some(session) else {
    @failure.reject("session-required", "Open a PPTX presentation first")
  }
  match operation {
    "controlShowPptx" =>
      session.control_show(
        field_int(request, "revision"),
        field_string(request, "action"),
        field_string(request, "slide"),
        xlsx_number(request, "time"),
        custom=match request {
          { "custom": String(id), .. } => Some(id)
          { "custom": _, .. } =>
            @failure.reject(
              "invalid-operation", "Custom show identity must be a string",
            )
          _ => None
        },
        layout=match request {
          { "layoutId": _, .. } => Some(field_int(request, "layoutId"))
          _ => None
        },
        point=match request {
          { "x": _, .. } | { "y": _, .. } =>
            Some((xlsx_number(request, "x"), xlsx_number(request, "y")))
          _ => None
        },
      )
    "layoutShowPptx" =>
      session.show_layout(
        field_int(request, "revision"),
        xlsx_number(request, "time"),
        self.probe,
        xlsx_profile(request),
        self.images,
      )
    "queryPptx" => session.query()
    "dateTimePptx" =>
      session.set_date_time(
        field_int(request, "revision"),
        field_string(request, "dateTime"),
        self.probe,
        xlsx_profile(request),
      )
    "followPptxHyperlink" =>
      session.follow_hyperlink(field_int(request, "revision"))
    "findPptx" | "replacePptxMatches" =>
      self.pptx_search(session, operation, request)
    "editPptxSlides" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Slide edit is required")
      }
      let change = match field_string(change, "action") {
        "showSettings" => pptx_show_settings(change)
        "customShows" => {
          guard change is { "value": Array(items), .. } && items.length() <= 32 else {
            @failure.reject("invalid-operation", "Custom show list is required")
          }
          @pptx.CustomShows(
            items.map(item => {
              guard item is { "slides": Array(slides), .. } &&
                slides.length() <= 256 else {
                @failure.reject(
                  "invalid-operation", "Custom show slide list is required",
                )
              }
              {
                id: field_string(item, "id"),
                name: field_string(item, "name"),
                slides: slides.map(value => {
                  match value {
                    String(value) => value
                    _ =>
                      @failure.reject(
                        "invalid-operation", "Custom show slide must be an identity",
                      )
                  }
                }),
              }
            }),
          )
        }
        "animations" => {
          guard change is { "value": Array(items), .. } && items.length() <= 128 else {
            @failure.reject("invalid-operation", "Animation list is required")
          }
          @pptx.Animations(
            items.map(item => {
              object: field_string(item, "object"),
              kind: field_string(item, "kind"),
              trigger: field_string(item, "trigger"),
              delay: field_int(item, "delay"),
              duration: field_int(item, "duration"),
              repeat: field_int(item, "repeat"),
              params: match item {
                { "params": Array(values), .. } if values.length() <= 2 =>
                  values.map(value => {
                    match value {
                      Number(value, ..) => value
                      _ =>
                        @failure.reject(
                          "invalid-operation", "Animation parameters must be numeric",
                        )
                    }
                  })
                _ =>
                  @failure.reject(
                    "invalid-operation", "Animation parameters are required",
                  )
              },
            }),
          )
        }
        "advance" => {
          let value = match change {
            { "value": value, .. } => value
            _ =>
              @failure.reject("invalid-operation", "Slide advance is required")
          }
          @pptx.Advance({
            click: xlsx_boolean(value, "click"),
            after: match value {
              { "after": Null, .. } => None
              { "after": _, .. } => Some(field_int(value, "after"))
              _ =>
                @failure.reject(
                  "invalid-operation", "Slide advance time is required",
                )
            },
          })
        }
        "transition" =>
          @pptx.Transition(
            match change {
              { "value": Null, .. } => None
              { "value": value, .. } =>
                Some({
                  kind: field_string(value, "kind"),
                  duration: field_int(value, "duration"),
                  direction: field_string(value, "direction"),
                })
              _ =>
                @failure.reject(
                  "invalid-operation", "Slide transition is required",
                )
            },
          )
        "add" => @pptx.AddSlide
        "copy" => @pptx.CopySlide
        "delete" => @pptx.DeleteSlide
        "move" => @pptx.MoveSlide(field_int(change, "index"))
        "hidden" => @pptx.HideSlide(xlsx_boolean(change, "hidden"))
        "notes" => @pptx.Notes(field_string(change, "text"))
        "firstSlideNumber" =>
          @pptx.FirstSlideNumber(xlsx_number(change, "number"))
        "footer" => {
          guard change is { "value": value, .. } else {
            @failure.reject(
              "invalid-operation", "Slide footer content is required",
            )
          }
          @pptx.Footer(
            {
              date: match value {
                { "date": Null, .. } => None
                { "date": String(text), .. } => Some(@pptx.Fixed(text))
                { "date": date, .. } =>
                  Some(
                    @pptx.Automatic(
                      field_int(date, "format"),
                      field_string(date, "language"),
                    ),
                  )
                _ =>
                  @failure.reject("invalid-operation", "Slide date is required")
              },
              footer: xlsx_optional_string(value, "footer"),
              number: xlsx_boolean(value, "number"),
            },
            xlsx_boolean(change, "allSlides"),
          )
        }
        "commentAdd" => {
          guard change is { "author": author, "parent": parent, .. } else {
            @failure.reject(
              "invalid-operation", "Comment author and reply parent are required",
            )
          }
          let parent = match parent {
            Null => None
            String(id) => Some(id)
            _ =>
              @failure.reject(
                "invalid-operation", "Invalid comment reply parent",
              )
          }
          @pptx.AddComment(
            field_string(change, "text"),
            field_string(author, "name"),
            field_string(author, "initials"),
            field_string(change, "date"),
            parent,
          )
        }
        "commentUpdate" =>
          @pptx.UpdateComment(
            field_string(change, "id"),
            field_string(change, "text"),
          )
        "commentRemove" => @pptx.RemoveComment(field_string(change, "id"))
        "themeColor" =>
          @pptx.ThemeColor(
            field_string(change, "slot"),
            field_string(change, "color"),
          )
        "themeFont" =>
          @pptx.ThemeFont(
            field_string(change, "kind"),
            field_string(change, "script"),
            field_string(change, "font"),
          )
        "sectionAdd" => @pptx.AddSection(field_string(change, "name"))
        "sectionRename" =>
          @pptx.RenameSection(
            field_string(change, "id"),
            field_string(change, "name"),
          )
        "sectionRemove" => @pptx.RemoveSection(field_string(change, "id"))
        "sectionRemoveAll" => @pptx.RemoveSections
        "sectionDelete" => @pptx.DeleteSection(field_string(change, "id"))
        "sectionMove" =>
          @pptx.MoveSection(
            field_string(change, "id"),
            field_int(change, "index"),
          )
        "size" =>
          @pptx.Size(
            xlsx_number(change, "width"),
            xlsx_number(change, "height"),
          )
        "backgroundImage" =>
          @pptx.BackgroundImage(
            input_bytes(change, 4194304),
            field_string(change, "mode"),
          )
        "backgroundImageInsets" =>
          @pptx.BackgroundImageInsets(pptx_image_insets(change))
        "backgroundImageFormat" => {
          guard change is { "crop": Array(values), .. } && values.length() == 4 else {
            @failure.reject(
              "invalid-operation", "Four crop values are required",
            )
          }
          let crop = values.map(value => {
            match value {
              Number(value, ..) => value
              _ => @failure.reject("invalid-operation", "Invalid crop value")
            }
          })
          @pptx.BackgroundImageFormat(
            field_string(change, "mode"),
            crop,
            xlsx_number(change, "opacity"),
          )
        }
        "background" => {
          let value = match change {
            { "value": Null, .. } => None
            { "value": { "kind": String("solid"), .. } as value, .. } =>
              Some(@pptx.Solid(field_string(value, "color")))
            { "value": { "kind": String("linear"), .. } as value, .. } =>
              Some(
                @pptx.Linear(
                  pptx_gradient_stops(value),
                  xlsx_number(value, "angle"),
                  xlsx_boolean(value, "scaled"),
                ),
              )
            _ =>
              @failure.reject(
                "invalid-operation", "Slide background requires a color or null",
              )
          }
          @pptx.Background(value)
        }
        "layout" => @pptx.ApplyLayout(field_string(change, "id"))
        "resetLayout" => @pptx.ResetLayout
        _ => @failure.reject("invalid-operation", "Unknown slide edit")
      }
      session.edit_slides(
        field_int(request, "revision"),
        field_string(request, "slide"),
        change,
        probe=self.probe,
        profile=xlsx_profile(request),
      )
    }
    "editPptxObjects" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Object edit is required")
      }
      let change = match field_string(change, "action") {
        "tableStructure" =>
          @pptx.TableStructure(field_string(change, "operation"))
        "tableRowHeight" => @pptx.TableRowHeight(xlsx_number(change, "value"))
        "tableColumnWidth" =>
          @pptx.TableColumnWidth(xlsx_number(change, "value"))
        "tableStyle" => @pptx.TableStyle(pptx_table_style(change))
        "splitTableCell" =>
          @pptx.SplitTableCell(
            field_int(change, "rows"),
            field_int(change, "columns"),
          )
        "imageFill" =>
          @pptx.ImageFill(
            pptx_objects(change),
            input_bytes(change, 4194304),
            field_string(change, "mode"),
          )
        "imageFillMode" => @pptx.ImageFillMode(field_string(change, "mode"))
        "imageMode" => @pptx.ImageMode(field_string(change, "mode"))
        "imageInsets" => @pptx.ImageInsets(pptx_image_insets(change))
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
        "insertTable" =>
          @pptx.InsertTable(
            field_int(change, "rows"),
            field_int(change, "columns"),
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
        "lineEnd" => {
          let side = field_string(change, "side")
          guard ["head", "tail"].contains(side) &&
            change is Object(fields) &&
            fields.keys().all(k => ["action", "side", "end"].contains(k)) &&
            fields.get("end") is Some(raw) else {
            @failure.reject(
              "invalid-operation", "Line end side and value are required",
            )
          }
          @pptx.StrokeEnd(
            side == "head",
            if raw is Null {
              None
            } else {
              guard raw is Object(fields) &&
                fields.keys().all(k => ["kind", "width", "length"].contains(k)) else {
                @failure.reject("invalid-operation", "Unknown line end fields")
              }
              Some({
                kind: field_string(raw, "kind"),
                width: field_string(raw, "width"),
                length: field_string(raw, "length"),
              })
            },
          )
        }
        "strokeCap" | "strokeJoin" => {
          let action = field_string(change, "action")
          let key = if action == "strokeCap" { "cap" } else { "join" }
          guard change is Object(fields) && fields.get(key) is Some(raw) else {
            @failure.reject("invalid-operation", "Border pen value is required")
          }
          let value = match raw {
            Null => None
            String(value) => Some(value)
            _ =>
              @failure.reject(
                "invalid-operation", "Border pen value is required",
              )
          }
          if action == "strokeCap" {
            @pptx.StrokeCap(value)
          } else {
            @pptx.StrokeJoin(
              value,
              if value == Some("miter") {
                xlsx_number(change, "miterLimit")
              } else {
                8
              },
            )
          }
        }
        "shapeAdjustment" =>
          @pptx.ShapeAdjustment(
            field_string(change, "name"),
            match change {
              { "value": Null, .. } => None
              _ => Some(xlsx_number(change, "value"))
            },
          )
        "hyperlink" =>
          match change {
            { "link": Null, .. } => @pptx.Hyperlink("none", "")
            {
              "link": { "kind": String(kind), "target": String(target), .. },
              ..
            } => @pptx.Hyperlink(kind, target)
            _ =>
              @failure.reject(
                "invalid-operation", "Hyperlink target is required",
              )
          }
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
        "fillOpacity" => @pptx.FillOpacity(xlsx_number(change, "opacity"))
        "gradientFill" =>
          @pptx.GradientFill(
            pptx_gradient_stops(change),
            xlsx_number(change, "angle"),
            xlsx_boolean(change, "scaled"),
          )
        "strokeOpacity" => @pptx.StrokeOpacity(xlsx_number(change, "opacity"))
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
    "printLayoutPptx" =>
      session.print_drawing(
        field_int(request, "revision"),
        xlsx_boolean(request, "all"),
        xlsx_boolean(request, "hidden"),
        self.probe,
        xlsx_profile(request),
        self.images,
      )
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
    "imageKeysPptx" | "imageKeysShowPptx" => {
      let keys = if operation == "imageKeysShowPptx" {
        session.show_image_keys()
      } else {
        session.image_keys(
          xlsx_boolean(request, "all"),
          xlsx_boolean(request, "hidden"),
        )
      }
      let retained = keys.copy()
      for key in session.image_keys(false, false) + session.show_image_keys() {
        if !retained.contains(key) {
          retained.push(key)
        }
      }
      guard retained.length() <= 256 else {
        @failure.reject("limit-exceeded", "Presentation images exceed 256")
      }
      // Keep the editor's current images while the slideshow prepares other pages.
      self.images.retain(retained)
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

///|
fn pptx_image_insets(change : Json) -> Array[Double] raise @failure.Failure {
  guard change is { "insets": Array(values), .. } && values.length() == 4 else {
    @failure.reject(
      "invalid-operation", "Four image destination insets are required",
    )
  }
  values.map(value => {
    match value {
      Number(value, ..) => value
      _ =>
        @failure.reject("invalid-operation", "Invalid image destination inset")
    }
  })
}

///|
fn pptx_gradient_stops(
  value : Json,
) -> Array[@layout.GradientStop] raise @failure.Failure {
  guard value is { "stops": Array(stops), .. } &&
    stops.length() >= 2 &&
    stops.length() <= 32 else {
    @failure.reject("invalid-operation", "Gradients require 2..32 stops")
  }
  stops.map(stop => {
    guard stop is Object(fields) &&
      fields.length() == 3 &&
      fields.contains("position") &&
      fields.contains("opacity") &&
      fields.contains("color") else {
      @failure.reject(
        "invalid-operation", "Gradient stops require position, color and opacity",
      )
    }
    {
      position: xlsx_number(stop, "position"),
      color: field_string(stop, "color"),
      opacity: xlsx_number(stop, "opacity"),
    }
  })
}
