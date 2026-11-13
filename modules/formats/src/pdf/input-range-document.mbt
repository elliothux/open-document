///|
priv struct PdfRangeDocument {
  reader : PdfRangeReader
  mut operation : String?
}

///|
/// Drop a suspended read after the host fails to provide a requested range.
pub fn PdfSession::cancel_preview_read(self : PdfSession) -> Unit {
  if self.ranged is Some(source) {
    self.document.sdk_clear_loaded_objects()
    source.operation = None
  }
}

///|
fn[T] PdfSession::read_source(
  self : PdfSession,
  operation : String,
  read : () -> T raise @failure.Failure,
) -> T raise @failure.Failure {
  if self.ranged is Some(source) {
    source.with_objects(self.document, operation, check_source => {
      let result = read()
      check_source()
      result
    })
  } else {
    read()
  }
}

///|
/// Open the page index for a read-only, seekable PDF session.
pub fn PdfRangeReader::open_preview(
  self : PdfRangeReader,
) -> PdfSession raise @failure.Failure {
  let pages = self.read_pages()
  let root = self.unencrypted_catalog()
  guard self.version is Some(version) && self.trailer is Some(trailer) else {
    @failure.reject("invalid-pdf", "Missing PDF source index")
  }
  let document = @pdflite.pdf_document_empty()
  document.set_version(version.major, version.minor)
  document.set_root(root)
  document.set_trailer_dict(trailer)
  let generations : Map[Int32, Int32] = Map([])
  for number, entry in self.entries {
    if entry.in_use {
      generations[number] = entry.generation
    }
  }
  PdfSession::from_source(
    document,
    b"",
    self.budget,
    generations,
    pages,
    0,
    "Range-backed PDF is read-only",
    ranged=Some({ reader: self, operation: None, }),
  )
}

///|
fn PdfRangeReader::original_bytes(
  self : PdfRangeReader,
) -> Bytes raise @failure.Failure {
  guard self.size <= self.budget.outputBytes else {
    @failure.reject("limit-exceeded", "PDF output exceeds budget")
  }
  self.read(0, self.size).to_owned()
}

///|
fn[T] PdfRangeDocument::with_objects(
  self : PdfRangeDocument,
  document : @pdflite.PdfDocument,
  operation : String,
  run : (() -> Unit raise @failure.Failure) -> T raise @failure.Failure,
) -> T raise @failure.Failure {
  if self.operation != Some(operation) {
    document.sdk_clear_loaded_objects()
    self.operation = Some(operation)
  }
  let pending : Ref[@failure.Failure?] = Ref(None)
  fn check_source() -> Unit raise @failure.Failure {
    if pending.val is Some(error) {
      raise error
    }
  }
  let result = pdf_bound(self.reader.budget, () => {
    document.sdk_with_object_loader(
      number => {
        guard pending.val is None &&
          self.reader.entries.get(number) is Some({ in_use: true, .. } as entry) else {
          return None
        }
        let object = self.reader.read_object(number) catch {
          @failure.Failure(..) as error => {
            pending.val = Some(error)
            // Stop interpreting this incomplete attempt at the next budget check.
            ignore(@pdfcore.sdk_allow(-1))
            return None
          }
        }
        Some((entry.generation, object))
      },
      () => run(check_source),
    )
  }) catch {
    @failure.Failure(..) as error => {
      let source_error = pending.val.unwrap_or(error)
      if !(source_error is @failure.Failure(code="source-range-required", ..)) {
        document.sdk_clear_loaded_objects()
        self.operation = None
      }
      raise source_error
    }
  }
  document.sdk_clear_loaded_objects()
  self.operation = None
  result
}
