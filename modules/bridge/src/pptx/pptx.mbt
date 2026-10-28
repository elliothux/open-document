///|
fn Context::pptx_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "openPptx" || operation == "createPptx" {
    guard self.pptx is None else {
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
        Some(value) => @model.Session::create(budget, date_time=value)
        None => @model.Session::create(budget)
      }
    } else {
      let bytes = input_bytes(
        request,
        budget.file_bytes.min(budget.retained_bytes),
      )
      match date_time {
        Some(value) => @model.Session::open(bytes, budget, date_time=value)
        None => @model.Session::open(bytes, budget)
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
    "mediaShowPptx" => pptx_show_media(session, request)
    "mediaBytesPptx" | "imageBytesPptx" =>
      pptx_resource_bytes(session, request, operation == "mediaBytesPptx")
    "inkShowPptx" => pptx_show_ink(session, request)
    "controlShowPptx" =>
      session.control_show(
        field_int(request, "revision"),
        field_string(request, "action"),
        field_string(request, "slide"),
        field_number(request, "time"),
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
            Some((field_number(request, "x"), field_number(request, "y")))
          _ => None
        },
      )
    "layoutShowPptx" =>
      session.show_layout(
        field_int(request, "revision"),
        field_number(request, "time"),
        self.probe,
        font_profile(request),
        self.images,
      )
    "queryPptx" => session.query()
    "inspectPptxSlides" | "importPptxSlides" =>
      self.pptx_import(session, request, operation == "importPptxSlides")
    "dateTimePptx" =>
      session.set_date_time(
        field_int(request, "revision"),
        field_string(request, "dateTime"),
        self.probe,
        font_profile(request),
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
        "guides" => pptx_guide_edit(change)
        "snapping" => pptx_snapping_edit(change)
        "showSettings" => pptx_show_settings(change)
        "customShows" => {
          guard change is { "value": Array(items), .. } && items.length() <= 32 else {
            @failure.reject("invalid-operation", "Custom show list is required")
          }
          @model.CustomShows(
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
          @model.Animations(
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
          @model.Advance({
            click: field_boolean(value, "click"),
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
          @model.Transition(
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
        "add" => @model.AddSlide
        "copy" => @model.CopySlide
        "delete" => @model.DeleteSlide
        "move" => @model.MoveSlide(field_int(change, "index"))
        "hidden" => @model.HideSlide(field_boolean(change, "hidden"))
        "notes" => @model.Notes(field_string(change, "text"))
        "firstSlideNumber" =>
          @model.FirstSlideNumber(field_number(change, "number"))
        "footer" => {
          guard change is { "value": value, .. } else {
            @failure.reject(
              "invalid-operation", "Slide footer content is required",
            )
          }
          @model.Footer(
            {
              date: match value {
                { "date": Null, .. } => None
                { "date": String(text), .. } => Some(@model.Fixed(text))
                { "date": date, .. } =>
                  Some(
                    @model.Automatic(
                      field_int(date, "format"),
                      field_string(date, "language"),
                    ),
                  )
                _ =>
                  @failure.reject("invalid-operation", "Slide date is required")
              },
              footer: optional_string(value, "footer"),
              number: field_boolean(value, "number"),
            },
            field_boolean(change, "allSlides"),
          )
        }
        "commentAdd" | "commentUpdate" | "commentRemove" | "commentStatus" =>
          pptx_comment_change(change)
        "themeColor" =>
          @model.ThemeColor(
            field_string(change, "slot"),
            field_string(change, "color"),
          )
        "themeFont" =>
          @model.ThemeFont(
            field_string(change, "kind"),
            field_string(change, "script"),
            field_string(change, "font"),
          )
        "masterTextStyle" | "masterParagraphStyle" =>
          pptx_master_text_style(change)
        "sectionAdd" => @model.AddSection(field_string(change, "name"))
        "sectionRename" =>
          @model.RenameSection(
            field_string(change, "id"),
            field_string(change, "name"),
          )
        "sectionRemove" => @model.RemoveSection(field_string(change, "id"))
        "sectionRemoveAll" => @model.RemoveSections
        "sectionDelete" => @model.DeleteSection(field_string(change, "id"))
        "sectionMove" =>
          @model.MoveSection(
            field_string(change, "id"),
            field_int(change, "index"),
          )
        "size" =>
          @model.Size(
            field_number(change, "width"),
            field_number(change, "height"),
          )
        "backgroundImage" =>
          @model.BackgroundImage(
            input_bytes(change, 4194304),
            field_string(change, "mode"),
          )
        "backgroundImageInsets" =>
          @model.BackgroundImageInsets(pptx_image_insets(change))
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
          @model.BackgroundImageFormat(
            field_string(change, "mode"),
            crop,
            field_number(change, "opacity"),
          )
        }
        "background" => {
          let value = match change {
            { "value": Null, .. } => None
            { "value": { "kind": String("solid"), .. } as value, .. } =>
              Some(@model.Solid(field_string(value, "color")))
            { "value": { "kind": String("linear"), .. } as value, .. } =>
              Some(
                @model.Linear(
                  pptx_gradient_stops(value),
                  field_number(value, "angle"),
                  field_boolean(value, "scaled"),
                ),
              )
            { "value": { "kind": String("radial"), .. } as value, .. } =>
              Some(@model.Radial(pptx_gradient_stops(value)))
            _ =>
              @failure.reject(
                "invalid-operation", "Slide background requires a color or null",
              )
          }
          @model.Background(value)
        }
        "layout" => @model.ApplyLayout(field_string(change, "id"))
        "resetLayout" => @model.ResetLayout
        "addLayout"
        | "copyLayout"
        | "deleteLayout"
        | "deleteMaster"
        | "addMaster"
        | "copyMaster"
        | "sourceName" => pptx_source_edit(change)
        _ => @failure.reject("invalid-operation", "Unknown slide edit")
      }
      session.edit_slides(
        field_int(request, "revision"),
        field_string(request, "slide"),
        change,
        probe=self.probe,
        profile=font_profile(request),
      )
    }
    "editPptxObjects" => {
      guard request is { "change": change, .. } else {
        @failure.reject("invalid-operation", "Object edit is required")
      }
      let change = match field_string(change, "action") {
        "tableStructure" =>
          @model.TableStructure(field_string(change, "operation"))
        "tableRowHeight" => @model.TableRowHeight(field_number(change, "value"))
        "tableColumnWidth" =>
          @model.TableColumnWidth(field_number(change, "value"))
        "tableStyle" => @model.TableStyle(pptx_table_style(change))
        "tableDirection" => @model.TableDirection(field_boolean(change, "rtl"))
        "splitTableCell" =>
          @model.SplitTableCell(
            field_int(change, "rows"),
            field_int(change, "columns"),
          )
        "imageFill" =>
          @model.ImageFill(
            pptx_objects(change),
            input_bytes(change, 4194304),
            field_string(change, "mode"),
          )
        "imageFillMode" => @model.ImageFillMode(field_string(change, "mode"))
        "imageMode" => @model.ImageMode(field_string(change, "mode"))
        "imageInsets" => @model.ImageInsets(pptx_image_insets(change))
        "imageOpacity" => @model.ImageOpacity(field_number(change, "opacity"))
        "replaceImage" =>
          @model.ReplaceImage(
            field_string(change, "object"),
            input_bytes(change, 4194304),
          )
        "imageCrop" =>
          @model.ImageCrop(
            field_number(change, "left"),
            field_number(change, "top"),
            field_number(change, "right"),
            field_number(change, "bottom"),
          )
        "insertMedia" | "fillMedia" => pptx_insert_media(change)
        "mediaPlayback" => pptx_media_playback(change)
        "insertImage" =>
          @model.InsertImage(
            input_bytes(change, 4194304),
            field_number(change, "x"),
            field_number(change, "y"),
            field_number(change, "width"),
            field_number(change, "height"),
          )
        "fillTable" =>
          @model.FillTable(
            field_int(change, "rows"),
            field_int(change, "columns"),
          )
        "insertTable" =>
          @model.InsertTable(
            field_int(change, "rows"),
            field_int(change, "columns"),
            field_number(change, "x"),
            field_number(change, "y"),
            field_number(change, "width"),
            field_number(change, "height"),
          )
        "insertChart" | "chartData" | "fillChart" =>
          pptx_chart_edit(
            change,
            field_string(change, "action") == "insertChart",
          )
        "insert" | "insertPlaceholder" => pptx_insert_object(change)
        "placeholder" => pptx_placeholder(change)
        "delete" => @model.Remove
        "clearTextFormat" => @model.ClearTextFormat
        "clearParagraphFormat" => @model.ClearParagraphFormat
        "textFormat" => {
          guard change is { "format": format, .. } else {
            @failure.reject("invalid-operation", "Text format is required")
          }
          @model.TextFormat(pptx_text_format(format))
        }
        "textAlign" => @model.TextAlign(field_string(change, "alignment"))
        "textParagraph" => {
          guard change is { "format": format, .. } else {
            @failure.reject("invalid-operation", "Paragraph format is required")
          }
          @model.TextParagraph(pptx_paragraph_format(format))
        }
        "textInsets"
        | "textAnchor"
        | "textWrap"
        | "textFit"
        | "textUpright"
        | "textRotation"
        | "textDirection"
        | "textColumns" => pptx_text_frame(change)
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
          @model.StrokeEnd(
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
            @model.StrokeCap(value)
          } else {
            @model.StrokeJoin(
              value,
              if value == Some("miter") {
                field_number(change, "miterLimit")
              } else {
                8
              },
            )
          }
        }
        "insertConnector" | "connectorEndpoints" => pptx_connector_edit(change)
        "insertDiagram" => pptx_diagram_edit(change)
        "insertWordArt" => pptx_word_art_edit(change)
        "insertMath" | "appendMath" | "updateMath" | "deleteMath" =>
          pptx_math_edit(change)
        "shapeAdjustment" =>
          @model.ShapeAdjustment(
            field_string(change, "name"),
            match change {
              { "value": Null, .. } => None
              _ => Some(field_number(change, "value"))
            },
          )
        "shapeType" => {
          guard change is Object(fields) &&
            fields.length() == 2 &&
            fields.keys().all(key => ["action", "preset"].contains(key)) else {
            @failure.reject("invalid-operation", "Invalid shape type fields")
          }
          @model.ShapeType(field_string(change, "preset"))
        }
        "hyperlink" =>
          match change {
            { "link": Null, .. } => @model.Hyperlink("none", "")
            {
              "link": { "kind": String(kind), "target": String(target), .. },
              ..
            } => @model.Hyperlink(kind, target)
            _ =>
              @failure.reject(
                "invalid-operation", "Hyperlink target is required",
              )
          }
        "strokeDash" =>
          @model.StrokeDash(
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
            @model.Fill(color)
          } else {
            @model.Stroke(color, field_number(change, "width"))
          }
        }
        "fillOpacity" => @model.FillOpacity(field_number(change, "opacity"))
        "gradientFill" | "radialGradientFill" => pptx_gradient_edit(change)
        "strokeOpacity" => @model.StrokeOpacity(field_number(change, "opacity"))
        "group" => @model.Group
        "ungroup" => @model.Ungroup
        "duplicate" =>
          @model.Duplicate(
            field_number(change, "dx"),
            field_number(change, "dy"),
          )
        "rotate" => @model.Rotate(field_number(change, "angle"))
        "flip" =>
          match field_string(change, "axis") {
            "horizontal" => @model.Flip(true)
            "vertical" => @model.Flip(false)
            _ => @failure.reject("invalid-operation", "Unknown flip axis")
          }
        "layer" => @model.Layer(field_string(change, "order"))
        "align" =>
          @model.Align(
            field_string(change, "alignment"),
            field_string(change, "relativeTo"),
          )
        "distribute" =>
          @model.Distribute(
            field_string(change, "axis"),
            field_string(change, "relativeTo"),
          )
        _ => @failure.reject("invalid-operation", "Unknown object edit")
      }
      session.edit_objects(
        field_int(request, "revision"),
        change,
        self.probe,
        font_profile(request),
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
        font_profile(request),
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
        field_boolean(request, "backward"),
        self.probe,
        font_profile(request),
      )
    "undoPptx" | "redoPptx" =>
      session.undo(field_int(request, "revision"), redo=operation == "redoPptx")
    "savePptx" =>
      { "bytes": @base64.encode(session.save(field_int(request, "revision"))) }
    "layoutPptx" =>
      session.layout(self.probe, font_profile(request), self.images)
    "printLayoutPptx" =>
      session.print_drawing(
        field_int(request, "revision"),
        field_boolean(request, "all"),
        field_boolean(request, "hidden"),
        self.probe,
        font_profile(request),
        self.images,
      )
    "hitPptx" =>
      session.hit(
        field_int(request, "layoutId"),
        field_number(request, "x"),
        field_number(request, "y"),
        field_number(request, "tolerance"),
        text=if request is Object(fields) && fields.contains("text") {
          field_boolean(request, "text")
        } else {
          false
        },
      )
    "selectionPptx" =>
      session.selection_geometry(
        field_int(request, "layoutId"),
        grid_scale=match request {
          { "gridScale": _, .. } => Some(field_number(request, "gridScale"))
          _ => None
        },
      )
    "navigatePptx" =>
      session.navigate(
        field_int(request, "revision"),
        field_int(request, "layoutId"),
        field_string(request, "direction"),
        field_boolean(request, "extend"),
      )
    "beginGuidePptx" =>
      session.begin_guide(
        field_int(request, "revision"),
        field_number(request, "x"),
        field_number(request, "y"),
        field_number(request, "tolerance"),
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
        field_number(request, "x"),
        field_number(request, "y"),
        field_number(request, "width"),
        field_number(request, "height"),
      )
    "dragPptx" =>
      session.drag(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        field_number(request, "dx"),
        field_number(request, "dy"),
        field_int(request, "handle"),
        shift=if request is Object(fields) && fields.contains("shift") {
          field_boolean(request, "shift")
        } else {
          false
        },
        center=if request is Object(fields) && fields.contains("center") {
          field_boolean(request, "center")
        } else {
          false
        },
        tolerance=if request is Object(fields) && fields.contains("tolerance") {
          field_number(request, "tolerance")
        } else {
          0
        },
      )
    "finishPptx" =>
      session.finish(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        self.probe,
        font_profile(request),
      )
    "cancelPptx" =>
      session.cancel(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
      )
    "copyPptx"
    | "pastePptxFragment"
    | "pastePptxObjects"
    | "objectFragmentImagesPptx"
    | "objectFragmentMediaPptx" =>
      self.pptx_clipboard(session, operation, request)
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
          field_boolean(request, "all"),
          field_boolean(request, "hidden"),
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
        field_boolean(request, "all"),
        field_boolean(request, "hidden"),
        self.probe,
        font_profile(request),
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
