///|
fn arrange_check_page(
  object : @syntax.PdfObject,
) -> Unit raise @failure.Failure {
  for key in ["StructParents", "B", "AA", "VP"] {
    guard raw(object, key) == @syntax.PdfNull else {
      @failure.reject(
        "protected-content",
        "Page arrangement is protected by " + key,
      )
    }
  }
}

///|
/// Split a page into distinct crop regions. Cropping retains hidden source data.
pub fn PdfSession::split_page(
  self : PdfSession,
  revision : Int32,
  id : String,
  regions : Array[PdfPlacement],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  let reason = self.page_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard regions.length() >= 2 &&
    self.pages.length() + regions.length() - 1 <= self.budget.pages else {
    @failure.reject("invalid-page", "Choose two or more bounded split regions")
  }
  for index, region in regions {
    check_pdf_placement(region)
    guard region.rotation == 0 &&
      region.x >= 0 &&
      region.y >= 0 &&
      region.x + region.width <= page.width + 0.000001 &&
      region.y + region.height <= page.height + 0.000001 else {
      @failure.reject(
        "invalid-page", "Split regions must fit inside the displayed page",
      )
    }
    for previous in regions[:index] {
      guard region.x >= previous.x + previous.width ||
        previous.x >= region.x + region.width ||
        region.y >= previous.y + previous.height ||
        previous.y >= region.y + region.height else {
        @failure.reject(
          "protected-content", "Overlapping split regions require explicit duplication of annotations and fields",
        )
      }
    }
  }
  pdf_bound(self.budget, () => {
    let original = tx.object(page.number)
    arrange_check_page(original)
    let parts : Array[SourcePage] = []
    let targets : Array[PdfArrangeTarget] = []
    let refs : Array[Array[@syntax.PdfObject]] = []
    let labels = self.page_labels()
    let partLabels : Map[Int32, @syntax.PdfObject] = Map([])
    for index, region in regions {
      let (x, y) = page.matrix.inverse().point(region.x, region.y)
      let (r, t) = page.matrix
        .inverse()
        .point(region.x + region.width, region.y + region.height)
      let crop = pdf_rectangle(x.min(r), y.min(t), x.max(r), y.max(t))
      let number = if index == 0 {
        page.number
      } else {
        guard tx.add(@syntax.PdfNull) is PdfIndirect(number) else {
          abort("Expected split page identity")
        }
        number
      }
      tx.objects[number] = original
        .deep_copy()
        .with_entry(pdf_name("CropBox"), crop)
        .with_entry(pdf_name("Annots"), @syntax.PdfArray([]))
      parts.push({
        ..page,
        number,
        generation: if index == 0 {
          page.generation
        } else {
          0
        },
        id: if index == 0 {
          page.id
        } else {
          "\{number}:0"
        },
        crop,
        width: region.width,
        height: region.height,
      })
      refs.push([])
      targets.push({ number, bounds: crop, matrix: @layout.Matrix::identity(), })
      if labels.get(page.number) is Some(label) {
        partLabels[number] = label.deep_copy()
      }
    }
    let seenAnnotations : Map[Int32, Bool] = Map([])
    for reference in annotation_refs(self.document, original) {
      guard reference is PdfIndirect(number) else {
        @failure.reject(
          "protected-content", "Direct annotations cannot be assigned safely to split pages",
        )
      }
      guard !seenAnnotations.contains(number) else {
        @failure.reject(
          "protected-content", "An annotation is attached more than once",
        )
      }
      seenAnnotations[number] = true
      let annotation = tx.object(number)
      for key in ["IRT", "Popup", "OC", "StructParent"] {
        guard raw(annotation, key) == @syntax.PdfNull else {
          @failure.reject(
            "protected-content",
            "Split annotation relationship is protected: " + key,
          )
        }
      }
      let flags = raw(annotation, "F")
      guard flags == @syntax.PdfNull ||
        (integer(flags) & (8 | 16 | 64 | 128 | 512)) == 0 else {
        @failure.reject(
          "protected-content", "Locked or fixed-view annotation cannot be reassigned",
        )
      }
      let (x, y, r, t) = rectangle(get(self.document, annotation, "Rect"))
      let matched : Array[Int32] = []
      for index, target in targets {
        if arrange_contains(target.bounds, x, y, r, t) {
          matched.push(index)
        }
      }
      guard matched.length() == 1 else {
        @failure.reject(
          "protected-content", "An annotation or widget crosses a split boundary or lies outside the selected regions",
        )
      }
      let index = matched[0]
      refs[index].push(reference)
      tx.objects[number] = annotation.with_entry(
        pdf_name("P"),
        @syntax.PdfIndirect(parts[index].number),
      )
    }
    for index, part in parts {
      tx.objects[part.number] = tx
        .object(part.number)
        .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs[index]))
    }
    let arranged : Array[SourcePage] = []
    for source in self.pages {
      if source.number == page.number {
        arranged.append(parts)
      } else {
        arranged.push(source)
      }
    }
    self.rebuild_pages(tx, arranged, labels=partLabels)
    tx.arrange_destinations(Map([(page.number, targets)]))
    tx.check_arranged_references(Map([(page.number, true)]))
    tx.commit(self.current)
  })
}

///|
/// Equal grid splitting is computed in the core's displayed-page coordinates.
pub fn PdfSession::split_page_grid(
  self : PdfSession,
  revision : Int32,
  id : String,
  columns : Int32,
  rows : Int32,
) -> Json raise @failure.Failure {
  self.check(revision)
  let page = self.page(id)
  guard columns >= 1 &&
    columns <= 16 &&
    rows >= 1 &&
    rows <= 16 &&
    columns * rows >= 2 else {
    @failure.reject(
      "invalid-page", "Page split grid must contain two to 256 regions",
    )
  }
  let regions : Array[PdfPlacement] = []
  for row in 0..<rows {
    for column in 0..<columns {
      let x = page.width * column.to_double() / columns.to_double()
      let y = page.height * row.to_double() / rows.to_double()
      let right = page.width * (column + 1).to_double() / columns.to_double()
      let bottom = page.height * (row + 1).to_double() / rows.to_double()
      regions.push({ x, y, width: right - x, height: bottom - y, rotation: 0, })
    }
  }
  self.split_page(revision, id, regions)
}
