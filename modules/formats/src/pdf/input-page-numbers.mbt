///|
fn contains_source_page_numbers(
  document : @pdflite.PdfDocument,
  bytes : Bytes,
  resources : @syntax.PdfObject,
  seen : Map[Int32, Bool],
  depth : Int32,
) -> Bool raise {
  @pdfcore.sdk_depth(depth)
  for op in @pdflite.pdf_parse_content_ops_from_view(bytes) {
    @pdfcore.sdk_check(1)
    if op is Op_Do(key) {
      let reference = raw(
        get(document, resources, "XObject"),
        @utf8.decode_lossy(key.bytes())[1:].to_owned(),
      )
      if reference is PdfIndirect(number) {
        if seen.contains(number) {
          continue
        }
        seen[number] = true
      }
      let object = resolve(document, reference)
      if !is_name(raw(object, "Subtype"), "Form") {
        continue
      }
      if is_name(raw(object, "ODRole"), "page-number") {
        return true
      }
      let nested = get(document, object, "Resources")
      if contains_source_page_numbers(
          document,
          stream_bytes(document, reference),
          if nested == @syntax.PdfNull {
            resources
          } else {
            nested
          },
          seen,
          depth + 1,
        ) {
        return true
      }
    }
  }
  false
}

///|
fn PdfTransaction::set_page_number(
  self : PdfTransaction,
  page : SourcePage,
  form : @syntax.PdfObject,
  spec : PdfTextSpec,
) -> Unit raise {
  let source = self.session.document
  let contents = page_contents(source, self.object(page.number))
  let seen : Map[Int32, Bool] = Map([])
  for reference in contents {
    let object = resolve(source, reference)
    if raw(object, "ODIdentity") != @syntax.PdfNull {
      continue
    }
    guard !contains_source_page_numbers(
      source,
      stream_bytes(source, reference),
      page.resources,
      seen,
      0,
    ) else {
      @failure.reject(
        "protected-content", "Page numbering nested in transformed source must be removed before resetting numbers",
      )
    }
  }
  let previous = self.session
    .owned_objects(page)
    .filter(object => {
      object.kind == "text" &&
      is_name(raw(resolve(source, object.form), "ODRole"), "page-number")
    })
  let retained = contents.filter(reference => {
    !previous.any(object => object.reference == reference)
  })
  self.objects[page.number] = self
    .object(page.number)
    .with_entry(pdf_name("Contents"), @syntax.PdfArray(retained))
  let block = self.place_form(page, form, spec.placement, spec.foreground)
  if !previous.is_empty() {
    guard block is PdfIndirect(number) &&
      self.object(number) is PdfStreamObject(stream) else {
      abort("Expected page number block")
    }
    self.objects[number] = @syntax.pdf_stream(
      stream.dictionary.with_entry(pdf_name("ODIdentity"), previous[0].marker),
      stream.data,
    )
  }
}
