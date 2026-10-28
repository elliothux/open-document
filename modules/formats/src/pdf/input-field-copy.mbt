///|
fn field_copy_has_reference(value : @syntax.PdfObject, depth : Int32) -> Bool {
  if depth >= 64 {
    return true
  }
  match value {
    PdfIndirect(_) | PdfStreamObject(_) => true
    PdfArray(items) =>
      items.any(item => field_copy_has_reference(item, depth + 1))
    PdfDictionary(entries) =>
      entries.any(pair => field_copy_has_reference(pair.1, depth + 1))
    _ => false
  }
}

///|
fn check_field_copy_dictionary(
  object : @syntax.PdfObject,
) -> Unit raise @failure.Failure {
  guard object is PdfDictionary(entries) else {
    @failure.reject(
      "protected-content", "Field and widget dictionaries must be ordinary objects",
    )
  }
  let known = [
    "FT", "Ff", "T", "TU", "TM", "V", "DV", "DA", "Q", "MaxLen", "Opt", "I", "TI",
    "Kids", "Parent", "ODFont", "Type", "Subtype", "P", "Rect", "F", "AP", "AS",
    "MK", "BS", "Border", "C", "CA", "NM", "M", "H",
  ]
  for (key, value) in entries {
    let key = @utf8.decode_lossy(key.bytes())[1:].to_owned()
    guard known.contains(key) || !field_copy_has_reference(value, 0) else {
      @failure.reject(
        "protected-content",
        "Unknown field relationship protects copying: " + key,
      )
    }
  }
}

///|
pub fn PdfSession::duplicate_field(
  self : PdfSession,
  revision : Int32,
  id : String,
  requested : String,
  dx : Double,
  dy : Double,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let field = self.design_field_target(id)
    check_pdf_text(requested)
    guard !dx.is_nan() &&
      !dy.is_nan() &&
      !dx.is_inf() &&
      !dy.is_inf() &&
      dx.abs() <= 14400 &&
      dy.abs() <= 14400 else {
      @failure.reject("invalid-position", "Field copy offset exceeds budget")
    }
    let object = tx.object(field.number)
    check_field_copy_dictionary(object)
    let partial = if raw(object, "T") == @syntax.PdfNull {
      ""
    } else {
      pdf_text_string(raw(object, "T"))
    }
    let prefix = if raw(object, "Parent") == @syntax.PdfNull {
      ""
    } else if partial.is_empty() {
      field.name + "."
    } else {
      field.name[:field.name.length() - partial.length()].to_owned()
    }
    let name = if !prefix.is_empty() && requested.has_prefix(prefix) {
      requested[prefix.length():].to_owned()
    } else {
      requested
    }
    guard !name.is_empty() &&
      !name.contains(".") &&
      !self.fields().any(other => other.name == prefix + name) else {
      @failure.reject(
        "invalid-operation", "Choose a unique field name within its existing group",
      )
    }
    guard tx.add(@syntax.PdfNull) is PdfIndirect(number) else {
      abort("Expected copied field identity")
    }
    let mut copied = object
      .deep_copy()
      .with_entry(pdf_name("T"), pdf_string(name))
    for key, value in field.attributes {
      copied = copied.with_entry(pdf_name(key), value.deep_copy())
    }
    let widgets : Array[@syntax.PdfObject] = []
    for (widgetNumber, pageId) in field.widgets {
      let page = self.page(pageId)
      let widget = self.document.lookup_object_or_null(widgetNumber)
      check_field_copy_dictionary(widget)
      let (x, y, r, t) = rectangle(get(self.document, widget, "Rect"))
      let (a, b) = page.matrix.point(x, y)
      let (c, d) = page.matrix.point(r, t)
      guard a.min(c) + dx >= 0 &&
        b.min(d) + dy >= 0 &&
        a.max(c) + dx <= page.width &&
        b.max(d) + dy <= page.height else {
        @failure.reject(
          "invalid-position", "Copied widgets must fit within their pages",
        )
      }
      let (nativeX, nativeY) = page.matrix.inverse().point(a + dx, b + dy)
      let (nativeR, nativeT) = page.matrix.inverse().point(c + dx, d + dy)
      let mut copy = if widgetNumber == field.number {
        copied
      } else {
        widget
        .deep_copy()
        .with_entry(pdf_name("Parent"), @syntax.PdfIndirect(number))
      }
      copy = copy
        .remove_dict_entry(pdf_name("NM"))
        .with_entry(
          pdf_name("Rect"),
          pdf_rectangle(
            nativeX.min(nativeR),
            nativeY.min(nativeT),
            nativeX.max(nativeR),
            nativeY.max(nativeT),
          ),
        )
      let reference = if widgetNumber == field.number {
        tx.objects[number] = copy
        @syntax.PdfIndirect(number)
      } else {
        tx.add(copy)
      }
      widgets.push(reference)
      let pageObject = tx.object(page.number)
      let refs = annotation_refs(self.document, pageObject)
      guard refs.length() < 4096 else {
        @failure.reject(
          "limit-exceeded", "Copied field widgets exceed page budget",
        )
      }
      tx.objects[page.number] = pageObject.with_entry(
        pdf_name("Annots"),
        @syntax.PdfArray(refs + [reference]),
      )
    }
    if field.widgets.length() != 1 || field.widgets[0].0 != field.number {
      copied = copied.with_entry(pdf_name("Kids"), @syntax.PdfArray(widgets))
      tx.objects[number] = copied
    }
    let parent = raw(object, "Parent")
    if parent is PdfIndirect(parentNumber) {
      let parentObject = tx.object(parentNumber)
      guard get(self.document, parentObject, "Kids") is PdfArray(kids) else {
        @failure.reject("protected-content", "Field parent is malformed")
      }
      tx.objects[parentNumber] = parentObject.with_entry(
        pdf_name("Kids"),
        @syntax.PdfArray(kids + [@syntax.PdfIndirect(number)]),
      )
    } else {
      guard parent == @syntax.PdfNull else {
        @failure.reject("protected-content", "Field parent must be indirect")
      }
      let catalog = tx.object(self.document.root())
      let formReference = raw(catalog, "AcroForm")
      let form = resolve(self.document, formReference)
      guard get(self.document, form, "Fields") is PdfArray(roots) &&
        roots.length() < 4096 else {
        @failure.reject(
          "protected-content", "Form field roots are malformed or excessive",
        )
      }
      let form = form.with_entry(
        pdf_name("Fields"),
        @syntax.PdfArray(roots + [@syntax.PdfIndirect(number)]),
      )
      if formReference is PdfIndirect(formNumber) {
        tx.objects[formNumber] = form
      } else {
        tx.objects[self.document.root()] = catalog.with_entry(
          pdf_name("AcroForm"),
          form,
        )
      }
    }
    tx.commit(self.current)
  })
}
