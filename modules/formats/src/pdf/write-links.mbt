///|
fn install_links(
  document : @pdflite.PdfDocument,
  layout : @layout.PositionedDocument,
  output_limit : Int,
) -> Unit raise {
  let links = layout.links
  guard links.length() <= 65536 else {
    @failure.reject("limit-exceeded", "PDF links exceed the output budget")
  }
  if links.is_empty() {
    return
  }
  let pages = document.page_reference_numbers()
  let annotations : Map[Int, Array[@syntax.PdfObject]] = Map([])
  let mut bytes = 0
  for link in links {
    let rect = link.rect
    guard rect.page >= 0 && rect.page < layout.pages.length() else {
      @failure.reject("invalid-drawing", "PDF link has an invalid page")
    }
    let page = layout.pages[rect.page]
    guard rect.x >= 0 &&
      rect.y >= 0 &&
      rect.width > 0 &&
      rect.height > 0 &&
      rect.x + rect.width <= page.width &&
      rect.y + rect.height <= page.height else {
      @failure.reject("invalid-drawing", "PDF link is outside the page")
    }
    let action = match link.target {
      External(uri) => {
        let lower = uri.to_lower()
        let prefix = if lower.has_prefix("https://") {
          8
        } else if lower.has_prefix("http://") || lower.has_prefix("mailto:") {
          7
        } else {
          0
        }
        guard prefix > 0 &&
          uri.length() > prefix &&
          uri.length() <= 2048 &&
          uri
          .iter()
          .all(c => {
            !c.is_whitespace() &&
            c.to_int() > 32 &&
            c.to_int() != 127 &&
            c != '\\'
          }) else {
          @failure.reject(
            "invalid-drawing", "PDF link requires a safe HTTP, HTTPS or mailto address",
          )
        }
        dict([("S", tag("URI")), ("URI", @syntax.PdfString(@utf8.encode(uri)))])
      }
      Internal(target, x, y) => {
        guard target >= 0 &&
          target < layout.pages.length() &&
          x >= 0 &&
          y >= 0 &&
          x <= layout.pages[target].width &&
          y <= layout.pages[target].height else {
          @failure.reject(
            "invalid-drawing", "PDF link has an invalid destination",
          )
        }
        dict([
          ("S", tag("GoTo")),
          (
            "D",
            @syntax.PdfArray([
              @syntax.PdfIndirect(pages[target]),
              tag("XYZ"),
              @syntax.PdfReal(x),
              @syntax.PdfReal(layout.pages[target].height - y),
              @syntax.PdfNull,
            ]),
          ),
        ])
      }
    }
    let annotation = dict([
      ("Type", tag("Annot")),
      ("Subtype", tag("Link")),
      (
        "Rect",
        @syntax.PdfArray([
          @syntax.PdfReal(rect.x),
          @syntax.PdfReal(page.height - rect.y - rect.height),
          @syntax.PdfReal(rect.x + rect.width),
          @syntax.PdfReal(page.height - rect.y),
        ]),
      ),
      (
        "Border",
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
        ]),
      ),
      ("A", action),
    ])
    bytes += @pdflite.pdf_write_object(annotation).length()
    guard bytes <= output_limit else {
      @failure.reject("limit-exceeded", "PDF links exceed the byte budget")
    }
    if !annotations.contains(rect.page) {
      annotations[rect.page] = []
    }
    annotations[rect.page].push(
      @syntax.PdfIndirect(document.add_object(annotation)),
    )
  }
  for page, items in annotations {
    guard document.lookup_object_or_null(pages[page])
      is @syntax.PdfDictionary(entries) else {
      @failure.reject("pdf-export-failed", "PDF page dictionary is missing")
    }
    document.add_object_given_number(
      pages[page],
      @syntax.PdfDictionary(
        entries + [(name("Annots"), @syntax.PdfArray(items))],
      ),
    )
  }
}
