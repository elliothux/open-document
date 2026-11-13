///|
fn PdfRangeReader::read_pages(
  self : PdfRangeReader,
) -> Array[SourcePage] raise @failure.Failure {
  if self.pages is Some(pages) {
    return pages
  }
  let root = self.unencrypted_catalog()
  let pages = pdf_bound(self.budget, () => {
    let catalog = self.page_index_object(root)
    fn resolve_tree(value : @syntax.PdfObject) -> @syntax.PdfObject raise {
      let seen : Map[Int32, Bool] = Map([])
      let mut current = value
      while current is @syntax.PdfIndirect(number) {
        @pdfcore.sdk_depth(seen.length())
        guard !seen.contains(number) else {
          @failure.reject("invalid-pdf", "Cyclic PDF page tree reference")
        }
        seen[number] = true
        current = self.page_index_object(number)
      }
      current
    }
    read_page_tree(
      catalog,
      resolve_tree,
      number => {
        self.entries.get(number).map(entry => entry.generation).unwrap_or(0)
      },
      self.budget,
    )
  }) catch {
    @failure.Failure(..) as error => {
      if !(error is @failure.Failure(code="source-range-required", ..)) {
        self.page_index_objects.clear()
      }
      raise error
    }
  }
  self.page_index_objects.clear()
  self.pages = Some(pages)
  pages
}

///|
fn PdfRangeReader::page_index_object(
  self : PdfRangeReader,
  number : Int32,
) -> @syntax.PdfObject raise {
  if self.page_index_objects.get(number) is Some(value) {
    return value
  }
  let value = self.read_object_value(number, Map([]))
  self.page_index_objects[number] = value
  value
}

///|
/// Read page identities, dimensions, and rotation from the page tree.
pub fn PdfRangeReader::pages(
  self : PdfRangeReader,
) -> Json raise @failure.Failure {
  ToJson::to_json(self.read_pages().map(SourcePage::query_page))
}
