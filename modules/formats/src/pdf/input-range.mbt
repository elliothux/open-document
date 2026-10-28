///|
fn check_pdf_offset(
  text : String,
  offset : Int32,
) -> Unit raise @failure.Failure {
  guard offset >= 0 && offset <= text.length() else {
    @failure.reject("invalid-selection", "PDF selection is outside page text")
  }
  guard offset == 0 ||
    offset == text.length() ||
    !(text[offset - 1].to_int() >= 0xd800 &&
    text[offset - 1].to_int() <= 0xdbff &&
    text[offset].to_int() >= 0xdc00 &&
    text[offset].to_int() <= 0xdfff) else {
    @failure.reject(
      "invalid-selection", "PDF selection splits a surrogate pair",
    )
  }
}

///|
fn PdfSession::range_result(
  self : PdfSession,
  anchorPage : String,
  anchor : Int32,
  focusPage : String,
  focus : Int32,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  ignore(self.page(anchorPage))
  ignore(self.page(focusPage))
  let mut first = 0
  let mut last = 0
  for index, page in self.pages {
    if page.id == anchorPage {
      first = index
    }
    if page.id == focusPage {
      last = index
    }
  }
  let forward = first < last || (first == last && anchor <= focus)
  let (startPage, start, endPage, end) = if forward {
    (first, anchor, last, focus)
  } else {
    (last, focus, first, anchor)
  }
  pdf_bound(self.budget, () => {
    let chunks : Array[String] = []
    let pages : Array[Json] = []
    let mut units = 0
    for index in startPage..<=endPage {
      let page = self.pages[index]
      let display = self.build_display(
        page.id,
        supplied,
        profile,
        @layout.Images::new(),
      )
      defer display.probe.close()
      let low = if index == startPage { start } else { 0 }
      let high = if index == endPage { end } else { display.text.length() }
      check_pdf_offset(display.text, low)
      check_pdf_offset(display.text, high)
      guard !display.spans.any(span => {
        !span.mapped && span.start < high && span.end > low
      }) else {
        @failure.reject("unmapped-text", "PDF range contains unknown Unicode")
      }
      guard display.textComplete || low == high else {
        @failure.reject(
          "unmapped-text", "PDF range crosses incomplete page text",
        )
      }
      units += high - low + 1
      guard units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "PDF cross-page selection exceeds budget",
        )
      }
      chunks.push(display.text[low:high].to_owned())
      pages.push({
        "page": page.id,
        "start": low,
        "end": high,
        "quads": display.spans
        .filter(span => span.start < high && span.end > low)
        .map(span => span.quad),
      })
    }
    { "revision": self.revision, "text": chunks.join("\n"), "pages": pages }
  })
}

///|
pub fn PdfSession::select_range(
  self : PdfSession,
  revision : Int32,
  anchorPage : String,
  anchor : Int32,
  focusPage : String,
  focus : Int32,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check(revision)
  let result = self.range_result(
    anchorPage, anchor, focusPage, focus, supplied, profile,
  )
  self.textRange = Some((anchorPage, anchor, focusPage, focus))
  result
}

///|
pub fn PdfSession::selected_range(
  self : PdfSession,
  revision : Int32,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check(revision)
  guard self.textRange is Some((a, b, c, d)) else {
    @failure.reject("invalid-selection", "No cross-page PDF selection")
  }
  self.range_result(a, b, c, d, supplied, profile)
}
