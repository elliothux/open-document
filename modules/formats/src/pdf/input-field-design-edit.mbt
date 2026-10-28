///|
fn field_edit_color(value : String, empty~ : Bool = false) -> Bool {
  (empty && value.is_empty()) ||
  (
    value.length() == 6 &&
    value.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string()))
  )
}

///|
fn checked_field_edit(
  session : PdfSession,
  field : FormField,
  spec : PdfFieldDesign,
  widgets : Array[PdfFieldWidgetDesign],
) -> (String, Array[(String, String)]) raise @failure.Failure {
  check_pdf_text(spec.name)
  check_pdf_text(spec.tooltip)
  guard spec.kind == field.kind &&
    spec.maxLength >= 0 &&
    spec.maxLength <= 32767 &&
    spec.size >= 0 &&
    spec.size <= 14400 &&
    field_edit_color(spec.color) &&
    !spec.font.is_empty() &&
    spec.font.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "Field design type or text style is invalid",
    )
  }
  let object = session.document.lookup_object_or_null(field.number)
  let partial = get(session.document, object, "T")
  let partial = if partial == @syntax.PdfNull {
    ""
  } else {
    pdf_text_string(partial)
  }
  let prefix = if raw(object, "Parent") == @syntax.PdfNull {
    ""
  } else if partial.is_empty() {
    field.name + "."
  } else {
    field.name[:field.name.length() - partial.length()].to_owned()
  }
  let name = if !prefix.is_empty() && spec.name.has_prefix(prefix) {
    spec.name[prefix.length():].to_owned()
  } else {
    spec.name
  }
  guard !name.is_empty() &&
    !name.contains(".") &&
    !session
    .fields()
    .any(other => other.id != field.id && other.name == prefix + name) else {
    @failure.reject(
      "invalid-operation", "Choose a unique field name within its existing group",
    )
  }
  guard widgets.length() == field.widgets.length() && !widgets.is_empty() else {
    @failure.reject(
      "protected-content", "Edit all existing widgets together; create a new field to change widget membership",
    )
  }
  let seen : Map[String, Bool] = Map([])
  for widget in widgets {
    check_pdf_placement(widget.placement)
    let page = session.page(widget.page)
    guard widget.placement.rotation == 0 &&
      widget.placement.x >= 0 &&
      widget.placement.y >= 0 &&
      widget.placement.x + widget.placement.width <= page.width &&
      widget.placement.y + widget.placement.height <= page.height &&
      widget.border >= 0 &&
      widget.border <= 100 &&
      field_edit_color(widget.borderColor) &&
      field_edit_color(widget.background, empty=true) &&
      !seen.contains(widget.id) &&
      field.widgets.any(original => {
        widget.id ==
        "\{original.0}:\{session.generations.get(original.0).unwrap_or(0)}"
      }) else {
      @failure.reject(
        "invalid-position", "Field widget identity, geometry or style is invalid",
      )
    }
    seen[widget.id] = true
  }
  let options = if ["radio", "choice", "list"].contains(field.kind) {
    choice_options(
      @syntax.PdfArray(
        spec.options.map(option => {
          @syntax.PdfArray([pdf_string(option.0), pdf_string(option.1)])
        }),
      ),
    )
  } else {
    []
  }
  if field.kind == "radio" {
    guard !options.any(option => option.0 == "Off") &&
      options.all(option => {
        widgets.any(widget => widget.exportValue == option.0)
      }) &&
      widgets.all(widget => {
        options.any(option => option.0 == widget.exportValue)
      }) else {
      @failure.reject(
        "invalid-operation", "Every radio export option must match an existing widget",
      )
    }
  }
  ignore(design_value(spec, spec.value))
  ignore(design_value(spec, spec.defaultValue))
  (name, options)
}

///|
fn field_edit_native_value(
  spec : PdfFieldDesign,
  value : Json,
  onState : String,
) -> @syntax.PdfObject raise @failure.Failure {
  let native = design_value(spec, value)
  if spec.kind == "checkbox" {
    tag(if value is True { onState } else { "Off" })
  } else {
    native
  }
}

///|
fn field_widget_by_id(
  session : PdfSession,
  field : FormField,
  id : String,
) -> (Int32, String) raise @failure.Failure {
  let selected = field.widgets.filter(widget => {
    id == "\{widget.0}:\{session.generations.get(widget.0).unwrap_or(0)}"
  })
  guard selected.length() == 1 else {
    @failure.reject("invalid-operation", "Unknown field widget")
  }
  selected[0]
}

///|
fn field_design_da(
  spec : PdfFieldDesign,
  font : String,
) -> @syntax.PdfObject raise {
  @syntax.PdfString(
    @pdflite.pdf_content_bytes_of_ops([
      @content.Op_Tf(pdf_name(font), spec.size),
      @content.Op_rg(
        channel(spec.color, 0),
        channel(spec.color, 2),
        channel(spec.color, 4),
      ),
    ]),
  )
}

///|
fn field_existing_font(field : FormField) -> String raise {
  guard field.attributes.get("DA") is Some(PdfString(bytes)) else {
    @failure.reject(
      "protected-content", "Variable-text field requires a default font",
    )
  }
  for op in @pdflite.pdf_parse_content_ops_from_view(bytes) {
    if op is Op_Tf(name, _) {
      return @utf8.decode_lossy(name.bytes())[1:].to_owned()
    }
  }
  @failure.reject(
    "protected-content", "Variable-text field requires a default font",
  )
}

///|
pub fn PdfSession::update_field_design(
  self : PdfSession,
  revision : Int32,
  id : String,
  spec : PdfFieldDesign,
  widgets : Array[PdfFieldWidgetDesign],
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let field = self.design_field_target(id)
    let originalWidgets = field.widgets.map(widget => {
      field_design_widget(self, field, widget.0, widget.1)
    })
    let originalSpec = field_design_spec(
      field,
      tx.object(field.number),
      originalWidgets,
    )
    let (name, options) = checked_field_edit(self, field, spec, widgets)
    if field_design_json(spec) == field_design_json(originalSpec) &&
      Json(widgets) == Json(originalWidgets) {
      return self.query()
    }
    let oldFlags = field.attributes.get("Ff").map(integer).unwrap_or(0)
    let flags = (oldFlags & -2101252) |
      (if spec.readOnly { 1 } else { 0 }) |
      (if spec.required { 2 } else { 0 }) |
      (if spec.kind == "text" && spec.multiline { 4096 } else { 0 }) |
      (if spec.kind == "list" && spec.multiSelect { 2097152 } else { 0 })
    let nativeValue = field_edit_native_value(spec, spec.value, field.onState)
    let defaultValue = field_edit_native_value(
      spec,
      spec.defaultValue,
      field.onState,
    )
    let variable = ["text", "choice", "list"].contains(field.kind)
    let fontStyleChanged = spec.font != originalSpec.font ||
      spec.size != originalSpec.size ||
      spec.color.to_lower() != originalSpec.color.to_lower() ||
      spec.multiline != originalSpec.multiline
    let valueChanged = spec.value != field.value
    let optionsChanged = options != originalSpec.options
    let workingDa = if variable {
      field_design_da(spec, field_existing_font(field))
    } else {
      @syntax.PdfNull
    }
    let attributes = field.attributes.copy()
    attributes["Ff"] = @syntax.PdfInteger(flags)
    attributes["MaxLen"] = @syntax.PdfInteger(spec.maxLength)
    if variable {
      attributes["DA"] = workingDa
      attributes["ODFont"] = pdf_string(spec.font)
    }
    let editedWidgets = widgets.map(widget => {
      let (number, _) = field_widget_by_id(self, field, widget.id)
      (number, widget.page)
    })
    let exports : Map[Int32, String] = Map([])
    for widget in widgets {
      if field.kind == "radio" {
        let (number, _) = field_widget_by_id(self, field, widget.id)
        exports[number] = widget.exportValue
      }
    }
    let edited : FormField = {
      ..field,
      name: spec.name,
      value: spec.value,
      widgets: editedWidgets,
      attributes,
      multiline: spec.multiline || field.kind == "list",
      maxLength: spec.maxLength,
      options,
      exportStates: exports,
    }
    let profile = profile.copy()
    let identity = match @layout.font_profile_identity(profile, spec.font) {
      Some(identity) => Some(identity)
      None => @layout.font_profile_identity(profile, "form")
    }
    if identity is Some(identity) {
      profile["form"] = identity
    }
    let mut appearanceFont : @syntax.PdfObject? = None
    let mut charged : Int64 = 0
    let mut chargedUntil = tx.next
    for widget in widgets {
      let (number, previousPage) = field_widget_by_id(self, field, widget.id)
      let original = originalWidgets.filter(item => item.id == widget.id)[0]
      let page = self.page(widget.page)
      let p = widget.placement
      let (x, y) = page.matrix.inverse().point(p.x, p.y)
      let (r, t) = page.matrix.inverse().point(p.x + p.width, p.y + p.height)
      guard (r - x).abs() > widget.border && (t - y).abs() > widget.border else {
        @failure.reject(
          "invalid-position", "Field widget has no available inner area",
        )
      }
      let originalObject = tx.object(number)
      let mk = get(self.document, originalObject, "MK")
      let mk = if mk == @syntax.PdfNull { dict([]) } else { mk.deep_copy() }
      let mk = mk
        .with_entry(
          pdf_name("BC"),
          @syntax.PdfArray(
            [0, 2, 4].map(index => {
              @syntax.PdfReal(channel(widget.borderColor, index))
            }),
          ),
        )
        .with_entry(
          pdf_name("BG"),
          @syntax.PdfArray(
            if widget.background.is_empty() {
              []
            } else {
              [0, 2, 4].map(index => {
                @syntax.PdfReal(channel(widget.background, index))
              })
            },
          ),
        )
      let mut object = originalObject
        .with_entry(
          pdf_name("Rect"),
          pdf_rectangle(x.min(r), y.min(t), x.max(r), y.max(t)),
        )
        .with_entry(pdf_name("P"), @syntax.PdfIndirect(page.number))
        .with_entry(
          pdf_name("BS"),
          dict([("S", tag("S")), ("W", @syntax.PdfReal(widget.border))]),
        )
        .with_entry(pdf_name("MK"), mk)
      let sizeChanged = widget.placement.width != original.placement.width ||
        widget.placement.height != original.placement.height ||
        self.page(previousPage).unit != page.unit
      let styleChanged = widget.border != original.border ||
        widget.borderColor.to_lower() != original.borderColor.to_lower() ||
        widget.background.to_lower() != original.background.to_lower()
      if variable {
        tx.objects[number] = object
        if valueChanged ||
          optionsChanged ||
          fontStyleChanged ||
          sizeChanged ||
          styleChanged {
          let text = if field.kind == "text" {
            guard spec.value is String(text) else {
              abort("Expected checked text value")
            }
            text
          } else if field.kind == "choice" {
            guard spec.value is String(value) else {
              abort("Expected checked choice value")
            }
            let selected = options.filter(option => option.0 == value)
            if selected.is_empty() {
              ""
            } else {
              selected[0].1
            }
          } else {
            ""
          }
          let appearance = field_appearance(
            tx, edited, number, page, text, supplied, profile,
          )
          object = tx
            .object(number)
            .with_entry(pdf_name("AP"), dict([("N", appearance)]))
          if appearanceFont is None && appearance is PdfIndirect(ap) {
            guard raw(raw(tx.object(ap), "Resources"), "Font")
              is PdfDictionary(fonts) &&
              fonts.length() == 1 else {
              @failure.reject(
                "protected-content", "Field design requires one explicit font",
              )
            }
            appearanceFont = Some(fonts[0].1)
          }
        }
      } else {
        let exportName = if field.kind == "radio" {
          widget.exportValue
        } else {
          field.onState
        }
        let oldExport = if field.kind == "radio" {
          field.exportStates[number]
        } else {
          field.onState
        }
        let normal = get(
          self.document,
          get(self.document, originalObject, "AP"),
          "N",
        )
        let (off, on) = if styleChanged {
          let buttonSpec = {
            ..spec,
            color: widget.borderColor,
            border: widget.border,
            background: widget.background,
          }
          (
            tx.button_appearance(
              (r - x).abs(),
              (t - y).abs(),
              false,
              field.kind == "radio",
              buttonSpec,
            ),
            tx.button_appearance(
              (r - x).abs(),
              (t - y).abs(),
              true,
              field.kind == "radio",
              buttonSpec,
            ),
          )
        } else {
          (raw(normal, "Off"), raw(normal, oldExport))
        }
        object = object
          .with_entry(
            pdf_name("AP"),
            dict([("N", dict([("Off", off), (exportName, on)]))]),
          )
          .with_entry(
            pdf_name("AS"),
            tag(
              if is_name(nativeValue, exportName) {
                exportName
              } else {
                "Off"
              },
            ),
          )
        if field.kind == "radio" {
          object = object.with_entry(
            pdf_name("TU"),
            pdf_string(options.filter(option => option.0 == exportName)[0].1),
          )
        }
      }
      tx.objects[number] = object
      if previousPage != widget.page {
        let oldPage = self.page(previousPage)
        let previous = tx.object(oldPage.number)
        let refs = annotation_refs(self.document, previous).filter(reference => {
          reference != @syntax.PdfIndirect(number)
        })
        tx.objects[oldPage.number] = previous.with_entry(
          pdf_name("Annots"),
          @syntax.PdfArray(refs),
        )
        let target = tx.object(page.number)
        let refs = annotation_refs(self.document, target)
        guard refs.length() < 4096 else {
          @failure.reject("limit-exceeded", "Moved widgets exceed page budget")
        }
        tx.objects[page.number] = target.with_entry(
          pdf_name("Annots"),
          @syntax.PdfArray(refs + [@syntax.PdfIndirect(number)]),
        )
      }
      for created in chargedUntil..<tx.next {
        charged += object_size(tx.objects[created], 0, 8388608 - charged)
      }
      chargedUntil = tx.next
    }
    let mut object = tx
      .object(field.number)
      .with_entry(pdf_name("T"), pdf_string(name))
      .with_entry(pdf_name("TU"), pdf_string(spec.tooltip))
      .with_entry(pdf_name("Ff"), @syntax.PdfInteger(flags))
      .with_entry(pdf_name("V"), nativeValue)
      .with_entry(pdf_name("DV"), defaultValue)
    if field.kind == "text" {
      object = object.with_entry(
        pdf_name("MaxLen"),
        @syntax.PdfInteger(spec.maxLength),
      )
    }
    if field.kind == "choice" || field.kind == "list" {
      object = object.with_entry(
        pdf_name("Opt"),
        @syntax.PdfArray(
          options.map(option => {
            @syntax.PdfArray([pdf_string(option.0), pdf_string(option.1)])
          }),
        ),
      )
      let indices : Array[@syntax.PdfObject] = []
      for index, option in options {
        if spec.value == Json(option.0) ||
          (match spec.value {
            Array(values) => values.contains(Json(option.0))
            _ => false
          }) {
          indices.push(@syntax.PdfInteger(index))
        }
      }
      object = object.with_entry(pdf_name("I"), @syntax.PdfArray(indices))
    }
    if field.kind == "radio" && optionsChanged {
      object = object.with_entry(
        pdf_name("Opt"),
        @syntax.PdfArray(
          field.widgets.map(original => {
            let selected = widgets.filter(widget => {
                widget.id ==
                "\{original.0}:\{self.generations.get(original.0).unwrap_or(0)}"
              })[0]
            pdf_string(selected.exportValue)
          }),
        ),
      )
    }
    if appearanceFont is Some(font) {
      let catalog = tx.object(self.document.root())
      let formReference = raw(catalog, "AcroForm")
      let form = resolve(self.document, formReference)
      let resources = get(self.document, form, "DR")
      let resources = if resources == @syntax.PdfNull {
        dict([])
      } else {
        resources.deep_copy()
      }
      let fonts = get(self.document, resources, "Font")
      let fonts = if fonts == @syntax.PdfNull {
        dict([])
      } else {
        fonts.deep_copy()
      }
      let fontName = "ODEdit\{field.number}_\{tx.next}"
      guard raw(fonts, fontName) == @syntax.PdfNull else {
        @failure.reject(
          "protected-content", "Private field font identity is ambiguous",
        )
      }
      let form = form.with_entry(
        pdf_name("DR"),
        resources.with_entry(
          pdf_name("Font"),
          fonts.with_entry(pdf_name(fontName), font),
        ),
      )
      if formReference is PdfIndirect(number) {
        tx.objects[number] = form
      } else {
        tx.objects[self.document.root()] = catalog.with_entry(
          pdf_name("AcroForm"),
          form,
        )
      }
      object = object
        .with_entry(pdf_name("DA"), field_design_da(spec, fontName))
        .with_entry(pdf_name("ODFont"), pdf_string(spec.font))
    }
    tx.objects[field.number] = object
    tx.commit(self.current)
  })
}
