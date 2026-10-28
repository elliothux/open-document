///|
pub(all) struct PdfFieldWidgetDesign {
  id : String
  page : String
  placement : PdfPlacement
  border : Double
  borderColor : String
  background : String
  exportValue : String
} derive(ToJson)

///|
pub extend PdfFieldWidgetDesign with ToJson::{to_json}

///|
fn field_design_widget(
  session : PdfSession,
  field : FormField,
  widgetNumber : Int32,
  pageId : String,
) -> PdfFieldWidgetDesign raise @failure.Failure {
  let document = session.document
  let object = document.lookup_object_or_null(widgetNumber)
  let page = session.page(pageId)
  let (x, y, r, t) = rectangle(get(document, object, "Rect"))
  let (a, b) = page.matrix.point(x, y)
  let (c, d) = page.matrix.point(r, t)
  let mk = get(document, object, "MK")
  if mk is PdfDictionary(properties) {
    guard properties.all(property => {
      ["BC", "BG", "R"].any(key => property.0 == pdf_name(key))
    }) else {
      @failure.reject(
        "protected-content", "Widget icons or captions require explicit appearance editing",
      )
    }
    let rotation = get(document, mk, "R")
    guard rotation == @syntax.PdfNull || integer(rotation) == 0 else {
      @failure.reject(
        "protected-content", "Rotated widget appearances are protected",
      )
    }
  }
  let mut border = 1.0
  let bs = get(document, object, "BS")
  if bs != @syntax.PdfNull {
    let style = get(document, bs, "S")
    guard style == @syntax.PdfNull || is_name(style, "S") else {
      @failure.reject(
        "protected-content", "Only solid widget borders support design editing",
      )
    }
    let width = get(document, bs, "W")
    if width != @syntax.PdfNull {
      border = number(width)
    }
  } else {
    let value = get(document, object, "Border")
    if value != @syntax.PdfNull {
      guard value is PdfArray([horizontal, vertical, width]) &&
        number(horizontal) == 0 &&
        number(vertical) == 0 else {
        @failure.reject(
          "protected-content", "Rounded or dashed widget borders are protected",
        )
      }
      border = number(width)
    }
  }
  guard border >= 0 && border <= 100 else {
    @failure.reject(
      "protected-content", "Widget border width exceeds design limits",
    )
  }
  let color = widget_color(mk, "BC")
  let placement : PdfPlacement = {
    x: a.min(c),
    y: b.min(d),
    width: (c - a).abs(),
    height: (d - b).abs(),
    rotation: 0,
  }
  check_pdf_placement(placement)
  {
    id: "\{widgetNumber}:\{session.generations.get(widgetNumber).unwrap_or(0)}",
    page: pageId,
    placement,
    border,
    borderColor: if color.is_empty() {
      "000000"
    } else {
      color
    },
    background: widget_color(mk, "BG"),
    exportValue: if field.kind == "radio" {
      field.exportStates.get(widgetNumber).unwrap_or("")
    } else if field.kind == "checkbox" {
      field.onState
    } else {
      ""
    },
  }
}

///|
fn field_default_value(field : FormField) -> Json raise @failure.Failure {
  let value = field.attributes.get("DV").unwrap_or(@syntax.PdfNull)
  if field.kind == "checkbox" {
    guard value == @syntax.PdfNull ||
      is_name(value, "Off") ||
      is_name(value, field.onState) else {
      @failure.reject(
        "protected-content", "Checkbox default value is not an appearance export state",
      )
    }
    return Json(is_name(value, field.onState))
  }
  if field.kind == "radio" {
    if value == @syntax.PdfNull || is_name(value, "Off") {
      return Json("")
    }
    guard value is PdfNameObject(name) else {
      @failure.reject("protected-content", "Radio default value must be a name")
    }
    return Json(@utf8.decode_lossy(name.bytes())[1:].to_owned())
  }
  if field.kind == "list" {
    let values = match value {
      PdfNull => []
      PdfArray(items) => items.map(pdf_text_string)
      PdfString(_) => [pdf_text_string(value)]
      _ =>
        @failure.reject(
          "protected-content", "List default value is unsupported",
        )
    }
    return Json(values)
  }
  Json(if value == @syntax.PdfNull { "" } else { pdf_text_string(value) })
}

///|
fn field_design_spec(
  field : FormField,
  object : @syntax.PdfObject,
  widgets : Array[PdfFieldWidgetDesign],
) -> PdfFieldDesign raise {
  let flags = field.attributes.get("Ff").map(integer).unwrap_or(0)
  let mut font = "form"
  let mut size = 12.0
  let mut color = widgets[0].borderColor
  if ["text", "choice", "list"].contains(field.kind) {
    guard field.attributes.get("DA") is Some(PdfString(bytes)) else {
      @failure.reject(
        "protected-content", "Field design requires a supported default appearance",
      )
    }
    let mut found = false
    for op in @pdflite.pdf_parse_content_ops_from_view(bytes) {
      match op {
        Op_Tf(key, value) => {
          font = @utf8.decode_lossy(key.bytes())[1:].to_owned()
          size = value
          found = true
        }
        Op_g(value) => color = rgb([value])
        Op_rg(r, g, b) => color = rgb([r, g, b])
        _ =>
          @failure.reject(
            "protected-content", "Field default appearance is unsupported",
          )
      }
    }
    guard found && size >= 0 && size <= 14400 else {
      @failure.reject(
        "protected-content", "Field font size exceeds design limits",
      )
    }
  }
  if field.attributes.get("ODFont") is Some(value) {
    font = pdf_text_string(value)
  }
  guard !font.is_empty() && font.length() <= 256 else {
    @failure.reject(
      "protected-content", "Field font identity exceeds design limits",
    )
  }
  let tooltip = raw(object, "TU")
  let tooltip = if tooltip == @syntax.PdfNull {
    ""
  } else {
    pdf_text_string(tooltip)
  }
  check_pdf_text(tooltip)
  {
    name: field.name,
    tooltip,
    kind: field.kind,
    placement: widgets[0].placement,
    options: if field.kind == "checkbox" {
      []
    } else {
      field.options.copy()
    },
    value: field.value,
    defaultValue: field_default_value(field),
    readOnly: (flags & 1) != 0,
    required: (flags & 2) != 0,
    multiline: field.kind == "text" && field.multiline,
    multiSelect: field.kind == "list" && (flags & 2097152) != 0,
    maxLength: field.maxLength,
    font,
    size,
    color,
    background: widgets[0].background,
    border: widgets[0].border,
  }
}

///|
fn field_design_json(spec : PdfFieldDesign) -> Json {
  {
    "name": spec.name,
    "tooltip": spec.tooltip,
    "kind": spec.kind,
    "placement": spec.placement,
    "options": spec.options.map(option => {
      "value": option.0,
      "label": option.1,
    }),
    "value": spec.value,
    "defaultValue": spec.defaultValue,
    "readOnly": spec.readOnly,
    "required": spec.required,
    "multiline": spec.multiline,
    "multiSelect": spec.multiSelect,
    "maxLength": spec.maxLength,
    "font": spec.font,
    "size": spec.size,
    "color": spec.color,
    "background": spec.background,
    "border": spec.border,
  }
}

///|
pub fn PdfSession::field_design(
  self : PdfSession,
  revision : Int32,
  id : String,
) -> Json raise @failure.Failure {
  self.check(revision)
  pdf_bound(self.budget, () => {
    try {
      let field = self.design_field_target(id)
      guard !field.widgets.is_empty() else {
        @failure.reject(
          "protected-content", "Field design requires at least one attached widget",
        )
      }
      let widgets = field.widgets.map(widget => {
        field_design_widget(self, field, widget.0, widget.1)
      })
      let spec = field_design_spec(
        field,
        self.document.lookup_object_or_null(field.number),
        widgets,
      )
      {
        "revision": revision,
        "field": id,
        "spec": field_design_json(spec),
        "widgets": widgets,
        "readOnlyReason": "",
      }
    } catch {
      @failure.Failure(message~, ..) =>
        {
          "revision": revision,
          "field": id,
          "spec": Json::null(),
          "widgets": [],
          "readOnlyReason": message,
        }
      _ =>
        {
          "revision": revision,
          "field": id,
          "spec": Json::null(),
          "widgets": [],
          "readOnlyReason": "Malformed field appearance protects design editing",
        }
    }
  })
}
