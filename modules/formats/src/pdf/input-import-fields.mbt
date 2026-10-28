///|
fn rename_import_appearance(
  value : @syntax.PdfObject,
  fonts : Map[String, String],
) -> @syntax.PdfObject raise {
  if value == @syntax.PdfNull {
    return value
  }
  guard value is PdfString(bytes) else {
    @failure.reject(
      "protected-content", "Imported field appearance must be a string",
    )
  }
  let ops = @pdflite.pdf_parse_content_ops_from_view(bytes).map(op => {
    match op {
      Op_Tf(key, size) => {
        let original = @utf8.decode_lossy(key.bytes())[1:].to_owned()
        guard fonts.get(original) is Some(replacement) else {
          @failure.reject(
            "protected-content", "Imported field font is not in AcroForm resources",
          )
        }
        @content.Op_Tf(pdf_name(replacement), size)
      }
      Op_g(_) | Op_rg(_, _, _) => op
      _ =>
        @failure.reject(
          "protected-content", "Imported default field appearance is unsupported",
        )
    }
  })
  @syntax.PdfString(@pdflite.pdf_content_bytes_of_ops(ops))
}

///|
/// Clone the selected part of the field tree before copying page annotations.
/// Shared field ancestors and appearances are copied once in this import.
fn PageImporter::prepare_fields(
  self : PageImporter,
  pages : Array[SourcePage],
) -> Unit raise {
  let selected : Map[String, Bool] = Map([])
  for page in pages {
    selected[page.id] = true
  }
  let sourceFields = self.source
    .fields()
    .filter(field => field.widgets.any(widget => selected.contains(widget.1)))
  if sourceFields.is_empty() {
    return
  }
  for field in sourceFields {
    guard field.reason.is_empty() || field.reason == "Read-only PDF field" else {
      @failure.reject("protected-content", "Imported field: " + field.reason)
    }
  }
  let catalog = resolve(
    self.source.document,
    @syntax.PdfIndirect(self.source.document.root()),
  )
  let sourceForm = get(self.source.document, catalog, "AcroForm")
  let targetCatalog = self.tx.object(self.tx.session.document.root())
  let formReference = raw(targetCatalog, "AcroForm")
  let mut targetForm = resolve(self.tx.session.document, formReference)
  if targetForm == @syntax.PdfNull {
    targetForm = dict([])
  }
  for key in ["XFA", "CO"] {
    guard raw(targetForm, key) == @syntax.PdfNull else {
      @failure.reject("protected-content", "Target form is protected: " + key)
    }
  }
  guard raw(targetForm, "NeedAppearances") != @syntax.PdfBoolean(true) else {
    @failure.reject(
      "protected-content", "Target form requires global appearance repair",
    )
  }
  let targetRoots = get(self.tx.session.document, targetForm, "Fields")
  let roots : Array[@syntax.PdfObject] = match targetRoots {
    PdfNull => []
    PdfArray(items) => items.copy()
    _ =>
      @failure.reject("protected-content", "Target field roots are malformed")
  }
  let targetResources = get(self.tx.session.document, targetForm, "DR")
  let targetResources = if targetResources == @syntax.PdfNull {
    dict([])
  } else {
    targetResources.deep_copy()
  }
  let targetFonts = get(self.tx.session.document, targetResources, "Font")
  let mut targetFonts = if targetFonts == @syntax.PdfNull {
    dict([])
  } else {
    targetFonts.deep_copy()
  }
  let sourceFonts = get(
    self.source.document,
    get(self.source.document, sourceForm, "DR"),
    "Font",
  )
  let renames : Map[String, String] = Map([])
  if sourceFonts is PdfDictionary(fonts) {
    for index, (key, reference) in fonts {
      let mut name = "ODImport\{self.tx.next}_\{index}"
      while raw(targetFonts, name) != @syntax.PdfNull {
        name += "_"
      }
      renames[@utf8.decode_lossy(key.bytes())[1:].to_owned()] = name
      targetFonts = targetFonts.with_entry(
        pdf_name(name),
        self.copy(reference, 0),
      )
    }
  }
  let terminal : Map[Int32, FormField] = Map([])
  for field in sourceFields {
    terminal[field.number] = field
  }
  let visited : Map[Int32, Bool] = Map([])
  let owners : Map[Int32, Int32] = Map([])
  fn prune(
    reference : @syntax.PdfObject,
    depth : Int32,
    root : Int32,
  ) -> @syntax.PdfObject? raise {
    guard depth < 64 &&
      reference is PdfIndirect(number) &&
      !visited.contains(number) &&
      visited.length() < 4096 else {
      @failure.reject(
        "protected-content", "Imported field tree is cyclic or excessive",
      )
    }
    visited[number] = true
    let mut object = self.source.document
      .lookup_object_or_null(number)
      .deep_copy()
    if terminal.get(number) is Some(field) {
      owners[number] = root
      let widgets = field.widgets.filter(widget => selected.contains(widget.1))
      if field.kind == "radio" {
        for key in ["V", "DV"] {
          let value = field.attributes.get(key).unwrap_or(@syntax.PdfNull)
          guard value == @syntax.PdfNull ||
            is_name(value, "Off") ||
            widgets.any(widget => {
              is_name(value, field.exportStates.get(widget.0).unwrap_or(""))
            }) else {
            @failure.reject(
              "protected-content", "Imported radio value belongs to a widget on an unselected page",
            )
          }
        }
      }
      let refs : Array[@syntax.PdfObject] = []
      for (widget, page) in widgets {
        let page = self.source.page(page)
        let widgetObject = if widget == number {
          object
        } else {
          self.source.document.lookup_object_or_null(widget)
        }
        guard widget == number ||
          raw(widgetObject, "Parent") == @syntax.PdfIndirect(number) else {
          @failure.reject(
            "protected-content", "Imported widget has an unexpected field parent",
          )
        }
        let mut widgetObject = widgetObject.with_entry(
          pdf_name("P"),
          @syntax.PdfIndirect(page.number),
        )
        if raw(widgetObject, "DA") != @syntax.PdfNull {
          widgetObject = widgetObject.with_entry(
            pdf_name("DA"),
            rename_import_appearance(raw(widgetObject, "DA"), renames),
          )
        }
        self.overrides[widget] = widgetObject
        refs.push(@syntax.PdfIndirect(widget))
      }
      if widgets.length() == 1 && widgets[0].0 == number {
        object = self.overrides[number]
      }
      for key, value in field.attributes {
        object = object.with_entry(pdf_name(key), value.deep_copy())
      }
      if widgets.length() != 1 || widgets[0].0 != number {
        object = object.with_entry(pdf_name("Kids"), @syntax.PdfArray(refs))
      }
      if field.attributes.get("DA") is Some(da) {
        object = object.with_entry(
          pdf_name("DA"),
          rename_import_appearance(da, renames),
        )
      }
      self.overrides[number] = object
      return Some(reference)
    }
    let kids = get(self.source.document, object, "Kids")
    guard kids is PdfArray(items) else { return None }
    let retained : Array[@syntax.PdfObject] = []
    for child in items {
      if prune(child, depth + 1, root) is Some(value) {
        retained.push(value)
      }
    }
    if retained.is_empty() {
      return None
    }
    object = object
      .with_entry(pdf_name("Kids"), @syntax.PdfArray(retained))
      .remove_dict_entry(pdf_name("DA"))
    self.overrides[number] = object
    Some(reference)
  }
  let sourceRoots = get(self.source.document, sourceForm, "Fields")
  guard sourceRoots is PdfArray(sourceRoots) else {
    @failure.reject("protected-content", "Imported field roots are malformed")
  }
  let kept : Array[@syntax.PdfObject] = []
  for root in sourceRoots {
    guard root is PdfIndirect(number) &&
      raw(self.source.document.lookup_object_or_null(number), "Parent") ==
      @syntax.PdfNull else {
      @failure.reject(
        "protected-content", "Imported field root has an unexpected parent",
      )
    }
    if prune(root, 0, number) is Some(reference) {
      kept.push(reference)
    }
  }
  let names : Map[String, Bool] = Map([])
  for field in self.tx.session.fields() {
    names[field.name] = true
  }
  for reference in kept {
    guard reference is PdfIndirect(number) else {
      abort("Expected imported field root")
    }
    let rootObject = self.overrides[number]
    let prefix = if raw(rootObject, "T") == @syntax.PdfNull {
      ""
    } else {
      pdf_text_string(raw(rootObject, "T"))
    }
    let descendants = sourceFields.filter(field => {
      owners.get(field.number) == Some(number)
    })
    let mut suffix = 0
    let mut chosen = prefix
    while descendants.any(field => {
            let name = if field.number == number {
              chosen
            } else if prefix.is_empty() {
              if chosen.is_empty() {
                field.name
              } else {
                chosen + "." + field.name
              }
            } else {
              chosen + field.name[prefix.length():].to_owned()
            }
            names.contains(name)
          }) {
      suffix += 1
      chosen = (if prefix.is_empty() { "Imported" } else { prefix }) +
        "_\{suffix}"
    }
    if chosen != prefix {
      self.overrides[number] = rootObject.with_entry(
        pdf_name("T"),
        pdf_string(chosen),
      )
    }
    for field in descendants {
      names[if field.number == number {
        chosen
      } else if prefix.is_empty() {
        if chosen.is_empty() {
          field.name
        } else {
          chosen + "." + field.name
        }
      } else {
        chosen + field.name[prefix.length():].to_owned()
      }] = true
    }
  }
  for number, _ in self.overrides {
    if !self.mapping.contains(number) {
      guard self.tx.add(@syntax.PdfNull) is PdfIndirect(id) else {
        abort("Expected imported field identity")
      }
      self.mapping[number] = id
    }
  }
  for number, object in self.overrides {
    self.tx.objects[self.mapping[number]] = self.copy(object, 0)
  }
  for root in kept {
    roots.push(self.copy(root, 0))
  }
  guard roots.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Imported form roots exceed budget")
  }
  targetForm = targetForm
    .with_entry(pdf_name("Fields"), @syntax.PdfArray(roots))
    .with_entry(
      pdf_name("DR"),
      targetResources.with_entry(pdf_name("Font"), targetFonts),
    )
  if formReference is PdfIndirect(number) {
    self.tx.objects[number] = targetForm
  } else {
    self.tx.objects[self.tx.session.document.root()] = targetCatalog.with_entry(
      pdf_name("AcroForm"),
      self.tx.add(targetForm),
    )
  }
}
