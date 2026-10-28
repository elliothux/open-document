///|
priv struct FormField {
  number : Int32
  id : String
  name : String
  kind : String
  value : Json
  widgets : Array[(Int32, String)]
  attributes : Map[String, @syntax.PdfObject]
  reason : String
  multiline : Bool
  maxLength : Int32
  onState : String
}

///|
fn PdfSession::fields(
  self : PdfSession,
) -> Array[FormField] raise @failure.Failure {
  let document = self.document
  let catalog = resolve(document, @syntax.PdfIndirect(document.root()))
  let form = get(document, catalog, "AcroForm")
  let roots = get(document, form, "Fields")
  if roots == @syntax.PdfNull {
    return []
  }
  guard roots is PdfArray(roots) else {
    @failure.reject("invalid-pdf", "AcroForm Fields must be an array")
  }
  let page_widgets : Map[Int32, String] = Map([])
  for page in self.pages {
    for
      reference in annotation_refs(
        document,
        document.lookup_object_or_null(page.number),
      ) {
      if reference is PdfIndirect(id) &&
        is_name(raw(resolve(document, reference), "Subtype"), "Widget") {
        guard !page_widgets.contains(id) && page_widgets.length() < 4096 else {
          @failure.reject("invalid-pdf", "Duplicate or excessive PDF widget")
        }
        page_widgets[id] = page.id
      }
    }
  }
  let base_reason = if raw(form, "XFA") != @syntax.PdfNull {
    "XFA forms are protected"
  } else if raw(form, "NeedAppearances") == @syntax.PdfBoolean(true) {
    "NeedAppearances requires unsupported global appearance repair"
  } else if raw(form, "CO") != @syntax.PdfNull {
    "Calculated forms are protected"
  } else {
    ""
  }
  let fields : Array[FormField] = []
  let visited : Map[Int32, Bool] = Map([])
  fn walk(
    reference : @syntax.PdfObject,
    parent : Map[String, @syntax.PdfObject],
    prefix : String,
    depth : Int32,
  ) -> Unit raise @failure.Failure {
    guard depth < 64 &&
      reference is PdfIndirect(id) &&
      !visited.contains(id) &&
      visited.length() < 4096 else {
      @failure.reject(
        "invalid-pdf", "Cyclic, direct, or excessive PDF field tree",
      )
    }
    visited[id] = true
    let object = resolve(document, reference)
    let attributes = parent.copy()
    for
      key in ["FT", "Ff", "V", "DV", "DA", "Q", "MaxLen", "AA", "A", "RV", "DS"] {
      let value = get(document, object, key)
      if value != @syntax.PdfNull {
        attributes[key] = value
      }
    }
    let partial = get(document, object, "T")
    let name = if partial == @syntax.PdfNull {
      prefix
    } else {
      (if prefix.is_empty() { "" } else { prefix + "." }) +
      pdf_text_string(partial)
    }
    guard name.length() <= 32767 else {
      @failure.reject("limit-exceeded", "PDF field name exceeds budget")
    }
    let kids = get(document, object, "Kids")
    let kids = match kids {
      PdfNull => []
      PdfArray(items) => items
      _ => @failure.reject("invalid-pdf", "PDF field Kids must be an array")
    }
    let terminal = kids.is_empty() ||
      kids.all(kid => {
        is_name(raw(resolve(document, kid), "Subtype"), "Widget") &&
        raw(resolve(document, kid), "T") == @syntax.PdfNull &&
        raw(resolve(document, kid), "FT") == @syntax.PdfNull
      })
    if !terminal {
      for child in kids {
        walk(child, attributes, name, depth + 1)
      }
      return
    }
    let widget_refs = if kids.is_empty() &&
      is_name(raw(object, "Subtype"), "Widget") {
      [reference]
    } else {
      kids
    }
    let widgets : Array[(Int32, String)] = []
    let mut reason = base_reason
    for widget in widget_refs {
      guard widget is PdfIndirect(number) else {
        @failure.reject("invalid-pdf", "PDF widget must be indirect")
      }
      let page = page_widgets.get(number).unwrap_or("")
      if page.is_empty() {
        reason = "Widget is not attached to a supported page"
      }
      let source = resolve(document, widget)
      let flags = get(document, source, "F")
      if flags != @syntax.PdfNull && (integer(flags) & (64 | 128 | 512)) != 0 {
        reason = "Locked PDF widget"
      }
      for key in ["A", "AA", "StructParent"] {
        if raw(source, key) != @syntax.PdfNull {
          reason = "Widget relationship is protected: " + key
        }
      }
      widgets.push((number, page))
    }
    if widgets.is_empty() {
      reason = "Field has no supported widget"
    }
    let flags = attributes.get("Ff").map(integer).unwrap_or(0)
    if (flags & 1) != 0 {
      reason = "Read-only PDF field"
    }
    for key in ["A", "AA", "RV", "DS"] {
      if attributes.contains(key) {
        reason = "Field action or rich text is protected: " + key
      }
    }
    let field_type = attributes.get("FT").unwrap_or(@syntax.PdfNull)
    let kind = if is_name(field_type, "Tx") {
      "text"
    } else if is_name(field_type, "Btn") && (flags & (32768 | 65536)) == 0 {
      "checkbox"
    } else {
      "unsupported"
    }
    let multiline = (flags & 4096) != 0
    if kind == "unsupported" ||
      (kind == "text" && (flags & (8192 | 1048576 | 16777216 | 33554432)) != 0) {
      reason = "Unsupported PDF field type or flags"
    }
    let max_length = attributes.get("MaxLen").map(integer).unwrap_or(32767)
    guard max_length >= 0 else {
      @failure.reject("invalid-pdf", "Negative PDF field MaxLen")
    }
    let source_value = attributes.get("V").unwrap_or(@syntax.PdfNull)
    let mut on_state = ""
    if kind == "checkbox" {
      for (number, _) in widgets {
        let normal = get(
          document,
          get(document, document.lookup_object_or_null(number), "AP"),
          "N",
        )
        if normal is PdfDictionary(states) {
          let on = states.filter(pair => pair.0 != pdf_name("Off"))
          if on.length() != 1 || get(document, normal, "Off") == @syntax.PdfNull {
            reason = "Checkbox requires Off and one actual export state"
          } else {
            let state = @utf8.decode_lossy(on[0].0.bytes())[1:].to_owned()
            if !on_state.is_empty() && on_state != state {
              reason = "Checkbox widgets have different export states"
            }
            on_state = state
            if !(resolve(document, on[0].1) is PdfStreamObject(_)) ||
              !(get(document, normal, "Off") is PdfStreamObject(_)) {
              reason = "Checkbox normal appearances are unsupported"
            }
          }
        } else {
          reason = "Checkbox has no state appearances"
        }
      }
    }
    let value : Json = if kind == "text" {
      let text = if source_value == @syntax.PdfNull {
        ""
      } else {
        pdf_text_string(source_value)
      }
      check_pdf_text(text)
      Json(text)
    } else if kind == "checkbox" {
      Json(is_name(source_value, on_state) && !on_state.is_empty())
    } else {
      Json::null()
    }
    fields.push({
      number: id,
      id: "\{id}:\{self.generations.get(id).unwrap_or(0)}",
      name,
      kind,
      value,
      widgets,
      attributes,
      reason,
      multiline,
      maxLength: max_length.min(32767),
      onState: on_state,
    })
  }
  let inherited : Map[String, @syntax.PdfObject] = Map([])
  for key in ["DA", "Q"] {
    let value = get(document, form, key)
    if value != @syntax.PdfNull {
      inherited[key] = value
    }
  }
  for reference in roots {
    walk(reference, inherited, "", 0)
  }
  fields
}

///|
fn field_json(field : FormField) -> Json {
  {
    "id": field.id,
    "name": field.name,
    "kind": field.kind,
    "value": field.value,
    "readOnlyReason": field.reason,
    "multiline": field.multiline,
    "maxLength": field.maxLength,
    "widgets": field.widgets.map(widget => {
      "id": widget.0.to_string(),
      "page": widget.1,
    }),
  }
}

///|
pub fn PdfSession::set_field(
  self : PdfSession,
  revision : Int32,
  id : String,
  value : Json,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let fields = self.fields()
    let mut selected : FormField? = None
    for field in fields {
      if field.id == id {
        selected = Some(field)
      }
    }
    guard selected is Some(field) else {
      @failure.reject("invalid-operation", "Unknown PDF field")
    }
    guard field.reason.is_empty() else {
      @failure.reject("protected-content", field.reason)
    }
    if field.kind == "checkbox" {
      guard value is (True | False) else {
        @failure.reject("invalid-operation", "Checkbox requires a boolean")
      }
      let state = if value is True { field.onState } else { "Off" }
      tx.objects[field.number] = tx
        .object(field.number)
        .with_entry(pdf_name("V"), tag(state))
      for (number, _) in field.widgets {
        tx.objects[number] = tx
          .object(number)
          .with_entry(pdf_name("AS"), tag(state))
      }
    } else {
      guard value is String(text) else {
        @failure.reject("invalid-operation", "Text field requires a string")
      }
      check_pdf_text(text)
      guard text.length() <= field.maxLength &&
        (field.multiline || (!text.contains("\n") && !text.contains("\r"))) else {
        @failure.reject(
          "invalid-text", "Text field exceeds MaxLen or single-line constraints",
        )
      }
      if value == field.value {
        return self.query()
      }
      for (number, page) in field.widgets {
        let appearance = field_appearance(
          tx,
          field,
          number,
          self.page(page),
          text,
          supplied,
          profile,
        )
        tx.objects[number] = tx
          .object(number)
          .with_entry(pdf_name("AP"), dict([("N", appearance)]))
      }
      tx.objects[field.number] = tx
        .object(field.number)
        .with_entry(pdf_name("V"), pdf_string(text))
    }
    tx.commit(self.current)
  })
}
