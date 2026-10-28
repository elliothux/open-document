///|
fn PdfSession::design_field_target(
  self : PdfSession,
  id : String,
) -> FormField raise @failure.Failure {
  let fields = self.fields()
  let selected = fields.filter(field => field.id == id)
  guard selected.length() == 1 else {
    @failure.reject("invalid-operation", "Unknown PDF field")
  }
  let field = selected[0]
  guard field.reason.is_empty() || field.reason == "Read-only PDF field" else {
    @failure.reject("protected-content", field.reason)
  }
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  let form = get(self.document, catalog, "AcroForm")
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull &&
    raw(form, "XFA") == @syntax.PdfNull &&
    raw(form, "CO") == @syntax.PdfNull &&
    raw(form, "NeedAppearances") != @syntax.PdfBoolean(true) else {
    @failure.reject(
      "protected-content", "Field tree relationships require explicit repair",
    )
  }
  guard !fields.any(field => {
    field.attributes.contains("A") || field.attributes.contains("AA")
  }) else {
    @failure.reject(
      "protected-content", "Field actions protect field names and relationships",
    )
  }
  for (number, _) in field.widgets {
    let widget = self.document.lookup_object_or_null(number)
    let flags = raw(widget, "F")
    guard flags == @syntax.PdfNull || (integer(flags) & (64 | 128 | 512)) == 0 else {
      @failure.reject("protected-content", "Locked PDF widget")
    }
    for key in ["A", "AA", "StructParent", "Popup", "IRT"] {
      guard raw(widget, key) == @syntax.PdfNull else {
        @failure.reject(
          "protected-content",
          "Widget relationship is protected: " + key,
        )
      }
    }
  }
  field
}

///|
pub fn PdfSession::rename_field(
  self : PdfSession,
  revision : Int32,
  id : String,
  requested : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let field = self.design_field_target(id)
    check_pdf_text(requested)
    let object = tx.object(field.number)
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
    guard !name.is_empty() && !name.contains(".") else {
      @failure.reject(
        "invalid-operation", "Rename the field within its existing group",
      )
    }
    let full = prefix + name
    guard !self.fields().any(other => other.id != id && other.name == full) else {
      @failure.reject("invalid-operation", "PDF field name already exists")
    }
    if full == field.name {
      return self.query()
    }
    tx.objects[field.number] = object.with_entry(
      pdf_name("T"),
      pdf_string(name),
    )
    tx.commit(self.current)
  })
}

///|
fn PdfTransaction::detach_field(
  self : PdfTransaction,
  number : Int32,
  removed : Map[Int32, Bool],
) -> Unit raise @failure.Failure {
  let mut current = number
  let visited : Map[Int32, Bool] = Map([])
  while true {
    guard visited.length() < 64 && !visited.contains(current) else {
      @failure.reject(
        "protected-content", "Field parent chain is cyclic or excessive",
      )
    }
    visited[current] = true
    removed[current] = true
    let object = self.object(current)
    let parent = raw(object, "Parent")
    if parent == @syntax.PdfNull {
      let catalogNumber = self.session.document.root()
      let catalog = self.object(catalogNumber)
      let reference = raw(catalog, "AcroForm")
      let form = resolve(self.session.document, reference)
      guard get(self.session.document, form, "Fields") is PdfArray(roots) &&
        roots.filter(root => root == @syntax.PdfIndirect(current)).length() == 1 else {
        @failure.reject(
          "protected-content", "Field is not attached to one form root",
        )
      }
      let form = form.with_entry(
        pdf_name("Fields"),
        @syntax.PdfArray(
          roots.filter(root => root != @syntax.PdfIndirect(current)),
        ),
      )
      if reference is PdfIndirect(formNumber) {
        self.objects[formNumber] = form
      } else {
        self.objects[catalogNumber] = catalog.with_entry(
          pdf_name("AcroForm"),
          form,
        )
      }
      break
    }
    guard parent is PdfIndirect(parentNumber) else {
      @failure.reject("protected-content", "Field parent must be indirect")
    }
    let parentObject = self.object(parentNumber)
    guard get(self.session.document, parentObject, "Kids") is PdfArray(kids) &&
      kids.filter(kid => kid == @syntax.PdfIndirect(current)).length() == 1 else {
      @failure.reject(
        "protected-content", "Field parent does not contain its child exactly once",
      )
    }
    let retained = kids.filter(kid => kid != @syntax.PdfIndirect(current))
    if !retained.is_empty() {
      self.objects[parentNumber] = parentObject.with_entry(
        pdf_name("Kids"),
        @syntax.PdfArray(retained),
      )
      break
    }
    current = parentNumber
  }
}

///|
pub fn PdfSession::delete_field(
  self : PdfSession,
  revision : Int32,
  id : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let field = self.design_field_target(id)
    let removed : Map[Int32, Bool] = Map([])
    for (number, _) in field.widgets {
      removed[number] = true
    }
    for page in self.pages {
      let object = tx.object(page.number)
      let refs = annotation_refs(self.document, object)
      let retained = refs.filter(reference => {
        match reference {
          PdfIndirect(number) => !removed.contains(number)
          _ => true
        }
      })
      if refs.length() != retained.length() {
        tx.objects[page.number] = object.with_entry(
          pdf_name("Annots"),
          @syntax.PdfArray(retained),
        )
      }
    }
    tx.detach_field(field.number, removed)
    let reachable = tx.reachable_objects()
    guard !removed.iter().any(entry => reachable.contains(entry.0)) else {
      @failure.reject(
        "protected-content", "Retained content still refers to the removed field or widget",
      )
    }
    tx.commit(self.current)
  })
}
