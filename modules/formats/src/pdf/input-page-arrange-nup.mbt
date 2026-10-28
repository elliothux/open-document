///|
fn PdfTransaction::arrange_page_form(
  self : PdfTransaction,
  page : SourcePage,
) -> @syntax.PdfObject raise {
  let original = self.session.document.lookup_object_or_null(page.number)
  let bytes = content_bytes(self.session.document, raw(original, "Contents"))
  let mut graphics = 0
  let mut text = 0
  for op in @pdflite.pdf_parse_content_ops_from_view(bytes) {
    match op {
      Op_q => graphics += 1
      Op_Q => graphics -= 1
      Op_BT => text += 1
      Op_ET => text -= 1
      _ => ()
    }
    guard graphics >= 0 && graphics <= 32 && text >= 0 && text <= 1 else {
      @failure.reject(
        "protected-content", "Page content cannot be isolated into one Form",
      )
    }
  }
  guard graphics == 0 && text == 0 else {
    @failure.reject(
      "protected-content", "Unbalanced page graphics or text state is protected",
    )
  }
  let flip : @layout.Matrix = { a: 1, b: 0, c: 0, d: -1, e: 0, f: page.height, }
  let prefix = @pdflite.pdf_content_bytes_of_ops([
    @content.Op_q,
    @content.Op_cm(geometry_matrix(flip.then(page.matrix))),
  ])
  let suffix = b"\nQ\n"
  let joined = Bytes::makei(
    prefix.length() + 1 + bytes.length() + suffix.length(),
    i => {
      if i < prefix.length() {
        prefix[i]
      } else if i == prefix.length() {
        b'\n'
      } else if i < prefix.length() + 1 + bytes.length() {
        bytes[i - prefix.length() - 1]
      } else {
        suffix[i - prefix.length() - 1 - bytes.length()]
      }
    },
  )
  let form = appearance_stream(
    joined,
    page.width,
    page.height,
    page.resources.deep_copy(),
  )
  guard form is PdfStreamObject(stream) else { abort("Expected page Form") }
  let group = raw(original, "Group")
  self.add(
    if group == @syntax.PdfNull {
      form
    } else {
      @syntax.pdf_stream(
        stream.dictionary.with_entry(pdf_name("Group"), group.deep_copy()),
        stream.data,
      )
    },
  )
}

///|
/// Compose selected pages as native Forms. It preserves live annotations and
/// redirects supported page destinations; the ordinary source payload remains.
pub fn PdfSession::nup_pages(
  self : PdfSession,
  revision : Int32,
  ids : Array[String],
  columns : Int32,
  rows : Int32,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let reason = self.page_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard !ids.is_empty() &&
    ids.length() <= self.budget.pages &&
    columns >= 1 &&
    columns <= 16 &&
    rows >= 1 &&
    rows <= 16 &&
    columns * rows >= 2 &&
    width > 0 &&
    width <= 14400 &&
    height > 0 &&
    height <= 14400 else {
    @failure.reject(
      "invalid-page", "N-up requires selected pages, bounded paper dimensions and a two-or-more-cell grid",
    )
  }
  let selected : Map[Int32, Bool] = Map([])
  let sources = ids.map(id => {
    let page = self.page(id)
    guard !selected.contains(page.number) else {
      @failure.reject("invalid-page", "Duplicate N-up source page")
    }
    selected[page.number] = true
    arrange_check_page(self.document.lookup_object_or_null(page.number))
    page
  })
  pdf_bound(self.budget, () => {
    let count = columns * rows
    let sheets : Array[SourcePage] = []
    let targets : Map[Int32, Array[PdfArrangeTarget]] = Map([])
    let box = pdf_rectangle(0, 0, width, height)
    let pageMatrix : @layout.Matrix = {
      a: 1,
      b: 0,
      c: 0,
      d: -1,
      e: 0,
      f: height,
    }
    for start = 0; start < sources.length(); start = start + count {
      let first = sources[start]
      let mut xobjects = dict([])
      let ops : Array[@content.PdfContentOp] = []
      let refs : Array[@syntax.PdfObject] = []
      for index in start..<(start + count).min(sources.length()) {
        let page = sources[index]
        let slot = index - start
        let cellWidth = width / columns.to_double()
        let cellHeight = height / rows.to_double()
        let scale = (cellWidth / page.width).min(cellHeight / page.height)
        let x = (slot % columns).to_double() * cellWidth +
          (cellWidth - page.width * scale) / 2
        let y = (slot / columns).to_double() * cellHeight +
          (cellHeight - page.height * scale) / 2
        let screen : @layout.Matrix = {
          a: scale,
          b: 0,
          c: 0,
          d: scale,
          e: x,
          f: y,
        }
        let sourceFlip : @layout.Matrix = {
          a: 1,
          b: 0,
          c: 0,
          d: -1,
          e: 0,
          f: page.height,
        }
        let placement = pageMatrix.inverse().then(screen).then(sourceFlip)
        let key = "ODPage\{index}"
        xobjects = xobjects.with_entry(
          pdf_name(key),
          tx.arrange_page_form(page),
        )
        ops.append([
          @content.Op_q,
          @content.Op_cm(geometry_matrix(placement)),
          @content.Op_Do(pdf_name(key)),
          @content.Op_Q,
        ])
        let transform = pageMatrix.inverse().then(screen).then(page.matrix)
        targets[page.number] = [
          {
            number: first.number,
            bounds: arrange_page_bounds(page),
            matrix: transform,
          },
        ]
        refs.append(
          annotation_refs(
            self.document,
            self.document.lookup_object_or_null(page.number),
          ),
        )
      }
      let resources = dict([("XObject", xobjects)])
      let sheet : SourcePage = {
        ..first,
        resources,
        media: box,
        crop: box,
        rotate: 0,
        unit: 1,
        width,
        height,
        matrix: pageMatrix,
      }
      let original = self.document.lookup_object_or_null(first.number)
      let contents = tx.add(stream(@pdflite.pdf_content_bytes_of_ops(ops), []))
      let mut object = original
        .deep_copy()
        .remove_dict_entry(pdf_name("Group"))
        .with_entry(pdf_name("Resources"), resources)
        .with_entry(pdf_name("Contents"), contents)
        .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs))
      for name in ["TrimBox", "BleedBox", "ArtBox"] {
        if raw(object, name) != @syntax.PdfNull {
          object = object.with_entry(pdf_name(name), box)
        }
      }
      tx.objects[first.number] = object
      sheets.push(sheet)
    }
    tx.arrange_fields(targets)
    let seenAnnotations : Map[Int32, Bool] = Map([])
    for page in sources {
      let target = targets[page.number][0]
      for
        reference in annotation_refs(
          self.document,
          self.document.lookup_object_or_null(page.number),
        ) {
        guard reference is PdfIndirect(number) &&
          !seenAnnotations.contains(number) else {
          @failure.reject(
            "protected-content", "An annotation is direct or attached more than once",
          )
        }
        seenAnnotations[number] = true
        ignore(tx.arrange_annotation(reference, target.number, target.matrix))
      }
    }
    let arranged : Array[SourcePage] = []
    let mut inserted = false
    for page in self.pages {
      if selected.contains(page.number) {
        if !inserted {
          arranged.append(sheets)
          inserted = true
        }
      } else {
        arranged.push(page)
      }
    }
    self.rebuild_pages(tx, arranged)
    tx.arrange_destinations(targets)
    tx.check_arranged_references(selected)
    let reachable = tx.reachable_objects()
    for page in sources {
      if !sheets.any(sheet => sheet.number == page.number) {
        guard !reachable.contains(page.number) else {
          @failure.reject(
            "protected-content", "An unknown retained relationship still refers to a merged source page",
          )
        }
      }
    }
    let current = self.page(self.current)
    tx.commit(
      if targets.get(current.number) is Some(target) {
        "\{target[0].number}:\{current.generation}"
      } else {
        self.current
      },
    )
  })
}
