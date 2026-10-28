///|
priv struct PageImporter {
  source : PdfSession
  tx : PdfTransaction
  mapping : Map[Int32, Int32]
}

///|
fn PageImporter::copy(
  self : PageImporter,
  value : @syntax.PdfObject,
  depth : Int32,
) -> @syntax.PdfObject raise {
  @pdfcore.sdk_depth(depth)
  @pdfcore.sdk_decoded(1)
  match value {
    PdfIndirect(number) => {
      if self.mapping.get(number) is Some(target) {
        return @syntax.PdfIndirect(target)
      }
      let original = self.source.document.lookup_object_or_null(number)
      guard !is_name(raw(original, "Type"), "Page") &&
        !is_name(raw(original, "Type"), "Pages") else {
        @failure.reject(
          "protected-content", "Imported destination refers to an unselected page",
        )
      }
      let reference = self.tx.add(@syntax.PdfNull)
      guard reference is PdfIndirect(target) else {
        abort("Expected indirect object")
      }
      self.mapping[number] = target
      self.tx.objects[target] = self.copy(original, depth + 1)
      reference
    }
    PdfArray(items) =>
      @syntax.PdfArray(items.map(item => self.copy(item, depth + 1)))
    PdfDictionary(entries) =>
      @syntax.PdfDictionary(
        entries.map(pair => (pair.0, self.copy(pair.1, depth + 1))),
      )
    PdfStreamObject(_) => {
      let bytes = value.deep_copy().stream_bytes()
      @pdfcore.sdk_decoded(bytes.length())
      let dictionary = match value {
        PdfStreamObject(s) => s.dictionary
        _ => dict([])
      }
      let dictionary = dictionary.with_entry(
        pdf_name("Length"),
        @syntax.PdfInteger(bytes.length()),
      )
      @syntax.pdf_stream(
        self.copy(dictionary, depth + 1),
        @syntax.StreamGot(bytes),
      )
    }
    _ => value.deep_copy()
  }
}

///|
/// Import selected pages in one transaction, retaining shared resources per import.
pub fn PdfSession::insert_pages(
  self : PdfSession,
  revision : Int32,
  bytes : Bytes,
  ids : Array[String],
  index : Int32,
  replace~ : Array[String] = [],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard bytes.length().to_int64() + self.original.length().to_int64() <=
    self.budget.fileBytes.to_int64() else {
    @failure.reject(
      "limit-exceeded", "Combined PDF import input exceeds budget",
    )
  }
  guard index >= 0 && index <= self.pages.length() else {
    @failure.reject(
      "invalid-page", "PDF insertion index is outside the document",
    )
  }
  let reason = self.page_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let removed : Map[Int32, Bool] = Map([])
  for id in replace {
    let page = self.page(id)
    guard !removed.contains(page.number) else {
      @failure.reject("invalid-page", "Duplicate replacement page")
    }
    removed[page.number] = true
  }
  for (number, _, value) in self.document.parsed_object_entries() {
    if !removed.is_empty() &&
      !removed.contains(number) &&
      !is_name(raw(value, "Type"), "Pages") &&
      references_any(value, removed, 0) {
      @failure.reject(
        "protected-content", "Retained content refers to a replaced PDF page",
      )
    }
  }
  let source = PdfSession::open(bytes, self.budget)
  defer source.close()
  guard source.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", source.readOnlyReason)
  }
  let sourceReason = source.page_order_reason()
  guard sourceReason.is_empty() else {
    @failure.reject("protected-content", sourceReason)
  }
  let selected = if ids.is_empty() {
    source.pages.copy()
  } else {
    ids.map(id => source.page(id))
  }
  guard !selected.is_empty() &&
    self.pages.length() - removed.length() + selected.length() <=
    self.budget.pages else {
    @failure.reject("limit-exceeded", "Imported PDF pages exceed budget")
  }
  pdf_bound(self.budget, () => {
    let mapping : Map[Int32, Int32] = Map([])
    for page in selected {
      guard !mapping.contains(page.number) else {
        @failure.reject("invalid-page", "Duplicate imported PDF page")
      }
      guard tx.add(@syntax.PdfNull) is PdfIndirect(number) else {
        abort("Expected indirect object")
      }
      mapping[page.number] = number
    }
    let importer : PageImporter = { source, tx, mapping, }
    let imported : Array[SourcePage] = []
    for page in selected {
      let sourceObject = source.document.lookup_object_or_null(page.number)
      for reference in annotation_refs(source.document, sourceObject) {
        let annotation = resolve(source.document, reference)
        guard !is_name(raw(annotation, "Subtype"), "Widget") else {
          @failure.reject(
            "protected-content", "Importing form widgets requires the complete field tree",
          )
        }
      }
      let number = mapping[page.number]
      let value = sourceObject
        .deep_copy()
        .remove_dict_entry(pdf_name("Parent"))
        .with_entry(pdf_name("Resources"), page.resources)
        .with_entry(pdf_name("MediaBox"), page.media)
        .with_entry(pdf_name("CropBox"), page.crop)
        .with_entry(pdf_name("Rotate"), @syntax.PdfInteger(page.rotate))
        .with_entry(pdf_name("UserUnit"), @syntax.PdfReal(page.unit))
      tx.objects[number] = importer.copy(value, 0)
      imported.push({
        ..page,
        number,
        generation: 0,
        id: "\{number}:0",
        resources: raw(tx.objects[number], "Resources"),
      })
    }
    let pages = self.pages[0:index]
      .to_owned()
      .filter(page => !removed.contains(page.number))
    for page in imported {
      pages.push(page)
    }
    for page in self.pages[index:] {
      if !removed.contains(page.number) {
        pages.push(page)
      }
    }
    self.rebuild_pages(tx, pages)
    tx.commit(
      if replace.contains(self.current) {
        imported[0].id
      } else {
        self.current
      },
    )
  })
}

///|
pub fn PdfSession::insert_blank(
  self : PdfSession,
  revision : Int32,
  index : Int32,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  self.check(revision)
  let blank = PdfSession::create(width, height, self.budget)
  defer blank.close()
  self.insert_pages(revision, blank.save(0), [], index)
}

///|
/// Extract pages into an independent document without changing source history.
pub fn PdfSession::extract_pages(
  self : PdfSession,
  revision : Int32,
  ids : Array[String],
) -> Bytes raise @failure.Failure {
  self.check(revision)
  guard !ids.is_empty() else {
    @failure.reject("invalid-page", "Select PDF pages to extract")
  }
  let target = PdfSession::create(595, 842, self.budget)
  defer target.close()
  let blank = target.current
  ignore(target.insert_pages(0, self.save(revision), ids, 1))
  ignore(target.delete_pages(1, [blank]))
  target.save(2)
}
