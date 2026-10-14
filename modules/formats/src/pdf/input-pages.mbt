///|
fn PdfSession::page_order_reason(
  self : PdfSession,
) -> String raise @failure.Failure {
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  for key in ["PageLabels", "StructTreeRoot", "Threads"] {
    if raw(catalog, key) != @syntax.PdfNull {
      return "Page order is protected by " + key
    }
  }
  for (_, _, object) in self.document.parsed_object_entries() {
    if numeric_destination(object, 0) {
      return "Unsupported numeric PDF destination protects page order"
    }
  }
  ""
}

///|
fn numeric_destination(object : @syntax.PdfObject, depth : Int) -> Bool {
  if depth >= 64 {
    return true
  }
  match object {
    PdfArray([PdfInteger(_), PdfNameObject(mode), ..]) if [
        "XYZ", "Fit", "FitB", "FitH", "FitV", "FitBH", "FitBV", "FitR",
      ].any(name => mode == pdf_name(name)) => true
    PdfArray(items) => items.any(item => numeric_destination(item, depth + 1))
    PdfDictionary(entries) =>
      entries.any(pair => numeric_destination(pair.1, depth + 1))
    PdfStreamObject(stream) => numeric_destination(stream.dictionary, depth + 1)
    _ => false
  }
}

///|
fn references_any(
  object : @syntax.PdfObject,
  targets : Map[Int, Bool],
  depth : Int,
) -> Bool {
  if depth >= 64 {
    return true
  }
  match object {
    PdfIndirect(n) => targets.contains(n)
    PdfArray(items) =>
      items.any(item => references_any(item, targets, depth + 1))
    PdfDictionary(entries) =>
      entries.any(pair => references_any(pair.1, targets, depth + 1))
    PdfStreamObject(stream) =>
      references_any(stream.dictionary, targets, depth + 1)
    _ => false
  }
}

///|
fn PdfSession::rebuild_pages(
  self : PdfSession,
  tx : PdfTransaction,
  pages : Array[SourcePage],
) -> Unit raise @failure.Failure {
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  guard raw(catalog, "Pages") is PdfIndirect(root) else {
    @failure.reject("invalid-pdf", "Page tree root must be indirect")
  }
  let tree = tx
    .object(root)
    .with_entry(
      pdf_name("Kids"),
      @syntax.PdfArray(pages.map(page => @syntax.PdfIndirect(page.number))),
    )
    .with_entry(pdf_name("Count"), @syntax.PdfInteger(pages.length()))
  tx.objects[root] = tree
  for page in pages {
    let value = tx
      .object(page.number)
      .with_entry(pdf_name("Parent"), @syntax.PdfIndirect(root))
      .with_entry(pdf_name("Resources"), page.resources)
      .with_entry(pdf_name("MediaBox"), page.media)
      .with_entry(pdf_name("CropBox"), page.crop)
      .with_entry(pdf_name("Rotate"), @syntax.PdfInteger(page.rotate))
      .with_entry(pdf_name("UserUnit"), @syntax.PdfReal(page.unit))
    tx.objects[page.number] = value
  }
}

///|
pub fn PdfSession::reorder(
  self : PdfSession,
  revision : Int,
  ids : Array[String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard ids.length() == self.pages.length() else {
    @failure.reject("invalid-page", "Reorder requires every current PDF page")
  }
  let seen : Map[String, Bool] = Map([])
  let pages = ids.map(id => {
    guard !seen.contains(id) else {
      @failure.reject("invalid-page", "Duplicate PDF page")
    }
    seen[id] = true
    self.page(id)
  })
  guard self.page_order_reason().is_empty() else {
    @failure.reject("protected-content", self.page_order_reason())
  }
  if ids == self.pages.map(page => page.id) {
    return self.query()
  }
  self.rebuild_pages(tx, pages)
  tx.commit(self.current)
}

///|
pub fn PdfSession::rotate_pages(
  self : PdfSession,
  revision : Int,
  ids : Array[String],
  degrees : Int,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard !ids.is_empty() &&
    degrees % 90 == 0 &&
    degrees >= -36000 &&
    degrees <= 36000 else {
    @failure.reject(
      "invalid-operation", "PDF rotation requires pages and bounded right angles",
    )
  }
  let seen : Map[String, Bool] = Map([])
  for id in ids {
    guard !seen.contains(id) else {
      @failure.reject("invalid-page", "Duplicate PDF page")
    }
    seen[id] = true
    let page = self.page(id)
    let angle = ((page.rotate + degrees) % 360 + 360) % 360
    if angle != page.rotate {
      tx.objects[page.number] = tx
        .object(page.number)
        .with_entry(pdf_name("Rotate"), @syntax.PdfInteger(angle))
    }
  }
  tx.commit(self.current)
}

///|
pub fn PdfSession::delete_pages(
  self : PdfSession,
  revision : Int,
  ids : Array[String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard !ids.is_empty() && ids.length() < self.pages.length() else {
    @failure.reject("invalid-page", "PDF must retain at least one page")
  }
  let reason = self.page_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let targets : Map[Int, Bool] = Map([])
  let own_annotations : Map[Int, Bool] = Map([])
  for id in ids {
    let page = self.page(id)
    guard !targets.contains(page.number) else {
      @failure.reject("invalid-page", "Duplicate PDF page")
    }
    targets[page.number] = true
    for
      reference in annotation_refs(
        self.document,
        self.document.lookup_object_or_null(page.number),
      ) {
      let object = resolve(self.document, reference)
      guard reference is PdfIndirect(n) &&
        (
          is_name(raw(object, "Subtype"), "Text") ||
          is_name(raw(object, "Subtype"), "Highlight") ||
          is_name(raw(object, "Subtype"), "Link")
        ) &&
        raw(object, "IRT") == @syntax.PdfNull &&
        raw(object, "Popup") == @syntax.PdfNull else {
        @failure.reject(
          "protected-content", "Page deletion is protected by widgets or unsupported annotation relationships",
        )
      }
      own_annotations[n] = true
    }
  }
  let protected_targets = targets.copy()
  for n, _ in own_annotations {
    protected_targets[n] = true
  }
  for (id, _, object) in self.document.parsed_object_entries() {
    if targets.contains(id) ||
      own_annotations.contains(id) ||
      is_name(raw(object, "Type"), "Pages") {
      continue
    }
    guard !references_any(object, protected_targets, 0) else {
      @failure.reject(
        "protected-content", "A retained PDF object refers to a deleted page or annotation",
      )
    }
  }
  let pages = self.pages.filter(page => !targets.contains(page.number))
  let mut current = self.current
  if ids.contains(current) {
    let mut passed = false
    let mut next : String? = None
    let mut previous = pages[0].id
    for page in self.pages {
      if page.id == self.current {
        passed = true
      }
      if !targets.contains(page.number) {
        if passed && next is None {
          next = Some(page.id)
        }
        if !passed {
          previous = page.id
        }
      }
    }
    current = next.unwrap_or(previous)
  }
  self.rebuild_pages(tx, pages)
  tx.commit(current)
}
