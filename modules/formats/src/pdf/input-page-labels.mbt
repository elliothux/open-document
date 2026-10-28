///|
fn PdfSession::page_labels(
  self : PdfSession,
) -> Map[Int32, @syntax.PdfObject] raise @failure.Failure {
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  let root = raw(catalog, "PageLabels")
  let result : Map[Int32, @syntax.PdfObject] = Map([])
  if root == @syntax.PdfNull {
    return result
  }
  let ranges : Map[Int32, @syntax.PdfObject] = Map([])
  let visited : Map[Int32, Bool] = Map([])
  let mut count = 0
  fn walk(
    reference : @syntax.PdfObject,
    depth : Int32,
  ) -> Unit raise @failure.Failure {
    guard depth < 32 && count < 4096 else {
      @failure.reject("protected-content", "Page label tree exceeds budget")
    }
    count += 1
    if reference is PdfIndirect(number) {
      guard !visited.contains(number) else {
        @failure.reject("protected-content", "Cyclic page label tree")
      }
      visited[number] = true
    }
    let object = resolve(self.document, reference)
    let nums = get(self.document, object, "Nums")
    let kids = get(self.document, object, "Kids")
    guard (nums == @syntax.PdfNull) != (kids == @syntax.PdfNull) else {
      @failure.reject("protected-content", "Ambiguous page label number tree")
    }
    if kids is PdfArray(children) {
      for child in children {
        walk(child, depth + 1)
      }
    } else {
      guard nums is PdfArray(entries) &&
        entries.length() % 2 == 0 &&
        entries.length() <= 2048 else {
        @failure.reject("protected-content", "Malformed page label ranges")
      }
      for i = 0; i < entries.length(); i = i + 2 {
        let index = integer(entries[i])
        guard index >= 0 &&
          index < self.pages.length() &&
          !ranges.contains(index) else {
          @failure.reject("protected-content", "Invalid page label range")
        }
        let label = resolve(self.document, entries[i + 1])
        guard label is PdfDictionary(properties) &&
          properties.all(pair => {
            ["S", "P", "St"].any(key => pair.0 == pdf_name(key))
          }) else {
          @failure.reject("protected-content", "Unknown page label properties")
        }
        let style = raw(label, "S")
        guard style == @syntax.PdfNull ||
          ["D", "R", "r", "A", "a"].any(key => is_name(style, key)) else {
          @failure.reject(
            "protected-content", "Unsupported page label numbering",
          )
        }
        let start = raw(label, "St")
        guard start == @syntax.PdfNull || integer(start) > 0 else {
          @failure.reject("protected-content", "Invalid page label start")
        }
        if raw(label, "P") != @syntax.PdfNull {
          check_pdf_text(pdf_text_string(raw(label, "P")))
        }
        ranges[index] = label
      }
    }
  }
  walk(root, 0)
  guard ranges.contains(0) else {
    @failure.reject("protected-content", "Page labels require an initial range")
  }
  let mut start = 0
  let mut current = ranges[0]
  for index, page in self.pages {
    if ranges.get(index) is Some(label) {
      start = index
      current = label
    }
    let value = if raw(current, "S") != @syntax.PdfNull {
      let first = raw(current, "St")
      let first = if first == @syntax.PdfNull { 1 } else { integer(first) }
      guard first <= 2147483647 - (index - start) else {
        @failure.reject("protected-content", "Page label sequence overflows")
      }
      current.with_entry(
        pdf_name("St"),
        @syntax.PdfInteger(first + index - start),
      )
    } else {
      current
    }
    result[page.number] = value
  }
  result
}

///|
fn PdfTransaction::rebuild_page_labels(
  self : PdfTransaction,
  pages : Array[SourcePage],
  imported : Map[Int32, @syntax.PdfObject],
) -> Unit raise @failure.Failure {
  let labels = self.session.page_labels()
  if labels.is_empty() && imported.is_empty() {
    return
  }
  let entries : Array[@syntax.PdfObject] = []
  for index, page in pages {
    let label = imported
      .get(page.number)
      .unwrap_or(
        labels
        .get(page.number)
        .unwrap_or(
          dict([("S", tag("D")), ("St", @syntax.PdfInteger(index + 1))]),
        ),
      )
    entries.append([@syntax.PdfInteger(index), label])
  }
  let catalog = self.session.document.root()
  self.objects[catalog] = self
    .object(catalog)
    .with_entry(
      pdf_name("PageLabels"),
      dict([("Nums", @syntax.PdfArray(entries))]),
    )
}
