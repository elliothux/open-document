///|
pub(all) struct PdfFieldDesign {
  name : String
  tooltip : String
  kind : String
  placement : PdfPlacement
  options : Array[(String, String)]
  value : Json
  defaultValue : Json
  readOnly : Bool
  required : Bool
  multiline : Bool
  multiSelect : Bool
  maxLength : Int32
  font : String
  size : Double
  color : String
  background : String
  border : Double
}

///|
fn design_value(
  spec : PdfFieldDesign,
  value : Json,
) -> @syntax.PdfObject raise @failure.Failure {
  if spec.kind == "checkbox" {
    guard value is (True | False) else {
      @failure.reject(
        "invalid-operation", "Checkbox design requires a boolean value",
      )
    }
    return tag(if value is True { "Yes" } else { "Off" })
  }
  if spec.kind == "list" {
    guard value is Array(values) &&
      values.length() <= spec.options.length() &&
      (spec.multiSelect || values.length() <= 1) else {
      @failure.reject(
        "invalid-operation", "List design values violate field constraints",
      )
    }
    let seen : Map[String, Bool] = Map([])
    let output : Array[@syntax.PdfObject] = []
    for value in values {
      guard value is String(text) &&
        !seen.contains(text) &&
        spec.options.any(option => option.0 == text) else {
        @failure.reject(
          "invalid-operation", "List design requires distinct export values",
        )
      }
      seen[text] = true
      output.push(pdf_string(text))
    }
    return @syntax.PdfArray(output)
  }
  guard value is String(text) else {
    @failure.reject("invalid-operation", "Field design requires a text value")
  }
  check_pdf_text(text)
  if spec.kind == "text" {
    guard text.length() <= spec.maxLength &&
      (spec.multiline || (!text.contains("\n") && !text.contains("\r"))) else {
      @failure.reject(
        "invalid-text", "Field design text violates length or line constraints",
      )
    }
    return pdf_string(text)
  }
  guard text.is_empty() || spec.options.any(option => option.0 == text) else {
    @failure.reject(
      "invalid-operation", "Field design value is not an export option",
    )
  }
  if spec.kind == "radio" {
    return tag(if text.is_empty() { "Off" } else { text })
  }
  pdf_string(text)
}

///|
fn PdfTransaction::button_appearance(
  self : PdfTransaction,
  width : Double,
  height : Double,
  on : Bool,
  radio : Bool,
  spec : PdfFieldDesign,
) -> @syntax.PdfObject raise {
  let ops : Array[@content.PdfContentOp] = [@content.Op_q]
  if !spec.background.is_empty() {
    ops.append([
      @content.Op_rg(
        channel(spec.background, 0),
        channel(spec.background, 2),
        channel(spec.background, 4),
      ),
      @content.Op_re(0, 0, width, height),
      @content.Op_f,
    ])
  }
  ops.append([
    @content.Op_RG(
      channel(spec.color, 0),
      channel(spec.color, 2),
      channel(spec.color, 4),
    ),
    @content.Op_w(spec.border.max(0.5)),
  ])
  if radio {
    let cx = width / 2
    let cy = height / 2
    let radius = (width.min(height) - spec.border).max(1) / 2
    let k = 0.5522847498307936
    if spec.border > 0 {
      ops.append([
        @content.Op_m(cx + radius, cy),
        @content.Op_c(
          cx + radius,
          cy + radius * k,
          cx + radius * k,
          cy + radius,
          cx,
          cy + radius,
        ),
        @content.Op_c(
          cx - radius * k,
          cy + radius,
          cx - radius,
          cy + radius * k,
          cx - radius,
          cy,
        ),
        @content.Op_c(
          cx - radius,
          cy - radius * k,
          cx - radius * k,
          cy - radius,
          cx,
          cy - radius,
        ),
        @content.Op_c(
          cx + radius * k,
          cy - radius,
          cx + radius,
          cy - radius * k,
          cx + radius,
          cy,
        ),
        @content.Op_h,
        @content.Op_S,
      ])
    }
    if on {
      ops.append([
        @content.Op_rg(
          channel(spec.color, 0),
          channel(spec.color, 2),
          channel(spec.color, 4),
        ),
        @content.Op_w(radius * 0.8),
        @content.Op_m(cx, cy),
        @content.Op_l(cx + 0.001, cy),
        @content.Op_J(1),
        @content.Op_S,
      ])
    }
  } else {
    if spec.border > 0 {
      ops.append([
        @content.Op_re(
          spec.border / 2,
          spec.border / 2,
          width - spec.border,
          height - spec.border,
        ),
        @content.Op_S,
      ])
    }
    if on {
      ops.append([
        @content.Op_w(width.min(height) / 8),
        @content.Op_m(width * 0.2, height * 0.5),
        @content.Op_l(width * 0.4, height * 0.25),
        @content.Op_l(width * 0.8, height * 0.8),
        @content.Op_S,
      ])
    }
  }
  ops.push(@content.Op_Q)
  self.add(
    appearance_stream(
      @pdflite.pdf_content_bytes_of_ops(ops),
      width,
      height,
      dict([]),
    ),
  )
}

///|
/// Create one terminal field and its widgets atomically, using native appearances.
pub fn PdfSession::create_field(
  self : PdfSession,
  revision : Int32,
  id : String,
  spec : PdfFieldDesign,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  check_pdf_placement(spec.placement)
  check_pdf_text(spec.name)
  check_pdf_text(spec.tooltip)
  guard !spec.name.is_empty() &&
    !spec.name.contains(".") &&
    ["text", "checkbox", "radio", "choice", "list"].contains(spec.kind) &&
    spec.placement.rotation == 0 &&
    page.rotate == 0 &&
    spec.placement.x >= 0 &&
    spec.placement.y >= 0 &&
    spec.placement.x + spec.placement.width <= page.width &&
    spec.placement.y + spec.placement.height <= page.height &&
    spec.maxLength >= 0 &&
    spec.maxLength <= 32767 &&
    spec.size >= 0 &&
    spec.size <= 14400 &&
    spec.border >= 0 &&
    spec.border <= 100 &&
    spec.color.length() == 6 &&
    spec.color.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string())) &&
    (
      spec.background.is_empty() ||
      (
        spec.background.length() == 6 &&
        spec.background
        .iter()
        .all(c => "0123456789abcdefABCDEF".contains(c.to_string()))
      )
    ) else {
    @failure.reject(
      "invalid-operation", "Field design name, geometry or style is invalid",
    )
  }
  guard !self.fields().any(field => field.name == spec.name) else {
    @failure.reject("invalid-operation", "PDF field name already exists")
  }
  let catalog = tx.object(self.document.root())
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull else {
    @failure.reject("protected-content", "Tagged field structure is protected")
  }
  let formReference = raw(catalog, "AcroForm")
  let form = resolve(self.document, formReference)
  let form = if form == @syntax.PdfNull { dict([]) } else { form.deep_copy() }
  guard raw(form, "XFA") == @syntax.PdfNull &&
    raw(form, "CO") == @syntax.PdfNull &&
    raw(form, "NeedAppearances") != @syntax.PdfBoolean(true) else {
    @failure.reject(
      "protected-content", "Field design requires an ordinary AcroForm",
    )
  }
  let roots = match get(self.document, form, "Fields") {
    PdfNull => []
    PdfArray(items) => items.copy()
    _ =>
      @failure.reject("protected-content", "AcroForm field roots are malformed")
  }
  guard roots.length() < 4096 else {
    @failure.reject("limit-exceeded", "PDF field count exceeds budget")
  }
  let options = if ["radio", "choice", "list"].contains(spec.kind) {
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
  guard spec.kind != "radio" || !options.any(option => option.0 == "Off") else {
    @failure.reject(
      "invalid-operation", "Off is reserved for an unselected radio widget",
    )
  }
  let value = design_value(spec, spec.value)
  let defaultValue = design_value(spec, spec.defaultValue)
  pdf_bound(self.budget, () => {
    let flags = (if spec.readOnly { 1 } else { 0 }) |
      (if spec.required { 2 } else { 0 }) |
      (if spec.kind == "text" && spec.multiline { 4096 } else { 0 }) |
      (if spec.kind == "radio" { 32768 } else { 0 }) |
      (if spec.kind == "choice" { 131072 } else { 0 }) |
      (if spec.kind == "list" && spec.multiSelect { 2097152 } else { 0 })
    let fieldType = if spec.kind == "text" {
      "Tx"
    } else if spec.kind == "radio" || spec.kind == "checkbox" {
      "Btn"
    } else {
      "Ch"
    }
    guard tx.add(dict([])) is PdfIndirect(fieldNumber) else {
      abort("Expected field identity")
    }
    let fontName = "ODField\{fieldNumber}"
    let da = @syntax.PdfString(
      @pdflite.pdf_content_bytes_of_ops([
        @content.Op_Tf(pdf_name(fontName), spec.size),
        @content.Op_rg(
          channel(spec.color, 0),
          channel(spec.color, 2),
          channel(spec.color, 4),
        ),
      ]),
    )
    let mut fieldObject = dict([
      ("FT", tag(fieldType)),
      ("Ff", @syntax.PdfInteger(flags)),
      ("T", pdf_string(spec.name)),
      ("TU", pdf_string(spec.tooltip)),
      ("V", value),
      ("DV", defaultValue),
      ("DA", da),
      ("MaxLen", @syntax.PdfInteger(spec.maxLength)),
      ("ODFont", pdf_string(spec.font)),
    ])
    if spec.kind == "checkbox" || spec.kind == "radio" {
      fieldObject = fieldObject
        .remove_dict_entry(pdf_name("DA"))
        .remove_dict_entry(pdf_name("MaxLen"))
    }
    if spec.kind == "choice" || spec.kind == "list" {
      fieldObject = fieldObject.with_entry(
        pdf_name("Opt"),
        @syntax.PdfArray(
          options.map(option => {
            @syntax.PdfArray([pdf_string(option.0), pdf_string(option.1)])
          }),
        ),
      )
    }
    let widgets : Array[(Int32, String)] = []
    let exportStates : Map[Int32, String] = Map([])
    let refs = annotation_refs(self.document, tx.object(page.number)).copy()
    let count = if spec.kind == "radio" { options.length() } else { 1 }
    guard count + refs.length() <= 4096 else {
      @failure.reject("limit-exceeded", "PDF widgets exceed page budget")
    }
    for index in 0..<count {
      let p = spec.placement
      let rowHeight = p.height / count.to_double()
      let width = if spec.kind == "radio" {
        p.width.min(rowHeight)
      } else {
        p.width
      }
      let inverse = page.matrix.inverse()
      let (x, y) = inverse.point(p.x, p.y + index.to_double() * rowHeight)
      let (r, t) = inverse.point(
        p.x + width,
        p.y + (index + 1).to_double() * rowHeight,
      )
      guard (r - x).abs() > spec.border && (t - y).abs() > spec.border else {
        @failure.reject(
          "invalid-position", "Widget has no available inner area",
        )
      }
      let mut widget = dict([
        ("Type", tag("Annot")),
        ("Subtype", tag("Widget")),
        ("Parent", @syntax.PdfIndirect(fieldNumber)),
        ("P", @syntax.PdfIndirect(page.number)),
        ("Rect", pdf_rectangle(x.min(r), y.min(t), x.max(r), y.max(t))),
        ("F", @syntax.PdfInteger(4)),
        ("BS", dict([("W", @syntax.PdfReal(spec.border)), ("S", tag("S"))])),
        (
          "MK",
          dict([
            (
              "BC",
              @syntax.PdfArray(
                [0, 2, 4].map(i => @syntax.PdfReal(channel(spec.color, i))),
              ),
            ),
            (
              "BG",
              @syntax.PdfArray(
                if spec.background.is_empty() {
                  []
                } else {
                  [0, 2, 4].map(i => {
                    @syntax.PdfReal(channel(spec.background, i))
                  })
                },
              ),
            ),
          ]),
        ),
      ])
      if spec.kind == "radio" || spec.kind == "checkbox" {
        let state = if spec.kind == "radio" { options[index].0 } else { "Yes" }
        let off = tx.button_appearance(
          (r - x).abs(),
          (t - y).abs(),
          false,
          spec.kind == "radio",
          spec,
        )
        let on = tx.button_appearance(
          (r - x).abs(),
          (t - y).abs(),
          true,
          spec.kind == "radio",
          spec,
        )
        widget = widget
          .with_entry(
            pdf_name("AP"),
            dict([("N", dict([("Off", off), (state, on)]))]),
          )
          .with_entry(
            pdf_name("AS"),
            tag(if is_name(value, state) { state } else { "Off" }),
          )
        if spec.kind == "radio" {
          widget = widget.with_entry(
            pdf_name("TU"),
            pdf_string(options[index].1),
          )
        }
      }
      guard tx.add(widget) is PdfIndirect(number) else {
        abort("Expected widget identity")
      }
      widgets.push((number, page.id))
      refs.push(@syntax.PdfIndirect(number))
      if spec.kind == "radio" {
        exportStates[number] = options[index].0
      }
    }
    fieldObject = fieldObject.with_entry(
      pdf_name("Kids"),
      @syntax.PdfArray(widgets.map(widget => @syntax.PdfIndirect(widget.0))),
    )
    tx.objects[fieldNumber] = fieldObject
    let field : FormField = {
      number: fieldNumber,
      id: "\{fieldNumber}:0",
      name: spec.name,
      kind: spec.kind,
      value: spec.value,
      widgets,
      attributes: Map([
        ("DA", da),
        ("Ff", @syntax.PdfInteger(flags & -3)),
        ("MaxLen", @syntax.PdfInteger(spec.maxLength)),
      ]),
      reason: "",
      multiline: spec.multiline || spec.kind == "list",
      maxLength: spec.maxLength,
      onState: "Yes",
      options,
      exportStates,
    }
    let profile = profile.copy()
    profile["form"] = @layout.font_profile_identity(profile, spec.font).unwrap_or(
      spec.font,
    )
    let mut form = form
    if spec.kind == "text" || spec.kind == "choice" || spec.kind == "list" {
      if spec.kind == "text" {
        guard spec.value is String(text) else {
          abort("Expected validated text value")
        }
        for (number, _) in widgets {
          let appearance = field_appearance(
            tx, field, number, page, text, supplied, profile,
          )
          tx.objects[number] = tx
            .object(number)
            .with_entry(pdf_name("AP"), dict([("N", appearance)]))
        }
      } else {
        tx.fill_option_field(field, spec.value, supplied, profile)
      }
      let ap = raw(raw(tx.object(widgets[0].0), "AP"), "N")
      guard ap is PdfIndirect(apNumber) else {
        abort("Expected generated field appearance")
      }
      let fonts = raw(raw(tx.object(apNumber), "Resources"), "Font")
      guard fonts is PdfDictionary(fonts) && fonts.length() == 1 else {
        @failure.reject(
          "protected-content", "Field design requires one explicit font",
        )
      }
      let resources = get(self.document, form, "DR")
      let resources = if resources == @syntax.PdfNull {
        dict([])
      } else {
        resources.deep_copy()
      }
      let existingFonts = get(self.document, resources, "Font")
      let existingFonts = if existingFonts == @syntax.PdfNull {
        dict([])
      } else {
        existingFonts.deep_copy()
      }
      form = form.with_entry(
        pdf_name("DR"),
        resources.with_entry(
          pdf_name("Font"),
          existingFonts.with_entry(pdf_name(fontName), fonts[0].1),
        ),
      )
    }
    roots.push(@syntax.PdfIndirect(fieldNumber))
    form = form.with_entry(pdf_name("Fields"), @syntax.PdfArray(roots))
    if formReference is PdfIndirect(number) {
      tx.objects[number] = form
    } else {
      tx.objects[self.document.root()] = catalog.with_entry(
        pdf_name("AcroForm"),
        tx.add(form),
      )
    }
    tx.objects[page.number] = tx
      .object(page.number)
      .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs))
    tx.commit(self.current)
  })
}
