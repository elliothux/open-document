///|
/// Create one blank page directly from native PDF objects.
pub fn PdfSession::create(
  width : Double,
  height : Double,
  budget : PdfBudget,
) -> PdfSession raise @failure.Failure {
  guard width > 0 && height > 0 && width <= 14400 && height <= 14400 else {
    @failure.reject(
      "invalid-page", "PDF page dimensions must be finite and within 14400 points",
    )
  }
  pdf_bound(budget, () => {
    guard budget.objects >= 4 && budget.objectNumber >= 4 else {
      @failure.reject("limit-exceeded", "Blank PDF requires four objects")
    }
    let document = @pdflite.pdf_document_empty()
    document.set_version(1, 7)
    document.add_object_given_number(
      1,
      dict([("Type", tag("Catalog")), ("Pages", @syntax.PdfIndirect(2))]),
    )
    document.add_object_given_number(
      2,
      dict([
        ("Type", tag("Pages")),
        ("Kids", @syntax.PdfArray([@syntax.PdfIndirect(3)])),
        ("Count", @syntax.PdfInteger(1)),
      ]),
    )
    document.add_object_given_number(
      3,
      dict([
        ("Type", tag("Page")),
        ("Parent", @syntax.PdfIndirect(2)),
        (
          "MediaBox",
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(0),
            @syntax.PdfReal(width),
            @syntax.PdfReal(height),
          ]),
        ),
        ("Resources", dict([])),
        ("Contents", @syntax.PdfIndirect(4)),
      ]),
    )
    document.add_object_given_number(4, stream(b"", []))
    document.set_root(1)
    let bytes = @pdflite.pdf_write_document(document)
    guard bytes.length() <= budget.outputBytes else {
      @failure.reject("limit-exceeded", "Blank PDF output exceeds budget")
    }
    PdfSession::open(bytes, budget)
  })
}
