///|
priv struct PdfArrangeTarget {
  number : Int32
  bounds : @syntax.PdfObject
  matrix : @layout.Matrix
}

///|
fn arrange_contains(
  bounds : @syntax.PdfObject,
  x : Double,
  y : Double,
  r : Double,
  t : Double,
) -> Bool raise @failure.Failure {
  let (a, b, c, d) = rectangle(bounds)
  x >= a - 0.000001 &&
  y >= b - 0.000001 &&
  r <= c + 0.000001 &&
  t <= d + 0.000001
}

///|
fn arrange_rect(
  bounds : @syntax.PdfObject,
  matrix : @layout.Matrix,
) -> @syntax.PdfObject raise @failure.Failure {
  let (x, y, r, t) = rectangle(bounds)
  let points = [(x, y), (r, y), (r, t), (x, t)].map(p => matrix.point(p.0, p.1))
  pdf_rectangle(
    points.map(p => p.0).fold(init=1000000000.0, Double::min),
    points.map(p => p.1).fold(init=1000000000.0, Double::min),
    points.map(p => p.0).fold(init=-1000000000.0, Double::max),
    points.map(p => p.1).fold(init=-1000000000.0, Double::max),
  )
}

///|
fn arrange_page_bounds(
  page : SourcePage,
) -> @syntax.PdfObject raise @failure.Failure {
  let (x, y, r, t) = rectangle(page.media)
  let (a, b, c, d) = rectangle(page.crop)
  pdf_rectangle(x.max(a), y.max(b), r.min(c), t.min(d))
}

///|
fn arrange_destination(
  value : @syntax.PdfObject,
  targets : Array[PdfArrangeTarget],
) -> @syntax.PdfObject raise @failure.Failure {
  guard value is PdfArray([_, PdfNameObject(mode), ..]) else {
    abort("Expected page destination")
  }
  guard value is PdfArray(items) && !targets.is_empty() else {
    abort("Expected destination targets")
  }
  let mode = @utf8.decode_lossy(mode.bytes())
  let mut target = targets[0]
  if mode == "/XYZ" && items.length() == 5 {
    if targets.length() > 1 {
      guard items[2] != @syntax.PdfNull && items[3] != @syntax.PdfNull else {
        @failure.reject(
          "protected-content", "A split-page XYZ destination needs both coordinates",
        )
      }
      let x = number(items[2])
      let y = number(items[3])
      let found = targets.filter(item => {
        arrange_contains(item.bounds, x, y, x, y)
      })
      guard !found.is_empty() else {
        @failure.reject(
          "protected-content", "A destination lies outside the split regions",
        )
      }
      target = found[0]
    }
    let m = target.matrix
    let x = if items[2] == @syntax.PdfNull {
      None
    } else {
      Some(number(items[2]))
    }
    let y = if items[3] == @syntax.PdfNull {
      None
    } else {
      Some(number(items[3]))
    }
    let mapped = fn(
      a : Double,
      b : Double,
      offset : Double,
    ) -> @syntax.PdfObject {
      if (a.abs() > 0.000001 && x is None) || (b.abs() > 0.000001 && y is None) {
        @syntax.PdfNull
      } else {
        @syntax.PdfReal(a * x.unwrap_or(0) + b * y.unwrap_or(0) + offset)
      }
    }
    let scale = (m.a * m.a + m.b * m.b).sqrt()
    let zoom = if items[4] == @syntax.PdfNull || number(items[4]) == 0 {
      items[4]
    } else {
      @syntax.PdfReal(number(items[4]) / scale)
    }
    return @syntax.PdfArray([
      @syntax.PdfIndirect(target.number),
      tag("XYZ"),
      mapped(m.a, m.c, m.e),
      mapped(m.b, m.d, m.f),
      zoom,
    ])
  }
  if mode == "/FitR" && items.length() == 6 {
    let x = number(items[2])
    let y = number(items[3])
    let r = number(items[4])
    let t = number(items[5])
    let found = targets.filter(item => arrange_contains(item.bounds, x, y, r, t))
    guard !found.is_empty() else {
      @failure.reject(
        "protected-content", "A FitR destination crosses split regions",
      )
    }
    target = found[0]
    let (a, b, c, d) = rectangle(
      arrange_rect(pdf_rectangle(x, y, r, t), target.matrix),
    )
    return @syntax.PdfArray([
      @syntax.PdfIndirect(target.number),
      tag("FitR"),
      @syntax.PdfReal(a),
      @syntax.PdfReal(b),
      @syntax.PdfReal(c),
      @syntax.PdfReal(d),
    ])
  }
  if ["/Fit", "/FitB"].contains(mode) && items.length() == 2 {
    let (x, y, r, t) = rectangle(arrange_rect(target.bounds, target.matrix))
    return @syntax.PdfArray([
      @syntax.PdfIndirect(target.number),
      tag("FitR"),
      @syntax.PdfReal(x),
      @syntax.PdfReal(y),
      @syntax.PdfReal(r),
      @syntax.PdfReal(t),
    ])
  }
  guard targets.length() == 1 &&
    items.length() == 3 &&
    ["/FitH", "/FitBH", "/FitV", "/FitBV"].contains(mode) else {
    @failure.reject(
      "protected-content", "The page destination cannot be assigned safely to an arranged page",
    )
  }
  let m = target.matrix
  let horizontal = mode == "/FitH" || mode == "/FitBH"
  let original = items[2]
  let mut converted = original
  let outputMode = if horizontal {
    if m.b.abs() <= 0.000001 && m.c.abs() <= 0.000001 {
      if original != @syntax.PdfNull {
        converted = @syntax.PdfReal(m.d * number(original) + m.f)
      }
      "FitH"
    } else if m.a.abs() <= 0.000001 && m.d.abs() <= 0.000001 {
      if original != @syntax.PdfNull {
        converted = @syntax.PdfReal(m.c * number(original) + m.e)
      }
      "FitV"
    } else {
      @failure.reject(
        "protected-content", "Skewed page destination is protected",
      )
    }
  } else if m.b.abs() <= 0.000001 && m.c.abs() <= 0.000001 {
    if original != @syntax.PdfNull {
      converted = @syntax.PdfReal(m.a * number(original) + m.e)
    }
    "FitV"
  } else if m.a.abs() <= 0.000001 && m.d.abs() <= 0.000001 {
    if original != @syntax.PdfNull {
      converted = @syntax.PdfReal(m.b * number(original) + m.f)
    }
    "FitH"
  } else {
    @failure.reject("protected-content", "Skewed page destination is protected")
  }
  @syntax.PdfArray([
    @syntax.PdfIndirect(target.number),
    tag(outputMode),
    converted,
  ])
}

///|
fn arrange_destinations(
  value : @syntax.PdfObject,
  targets : Map[Int32, Array[PdfArrangeTarget]],
  depth : Int32,
) -> @syntax.PdfObject raise {
  @pdfcore.sdk_check(1)
  @pdfcore.sdk_depth(depth)
  match value {
    PdfArray([PdfIndirect(number), PdfNameObject(mode), ..]) if targets.contains(
        number,
      ) &&
      ["XYZ", "Fit", "FitB", "FitH", "FitV", "FitBH", "FitBV", "FitR"].any(key => {
        mode == pdf_name(key)
      }) => arrange_destination(value, targets[number])
    PdfArray(items) =>
      @syntax.PdfArray(
        items.map(item => arrange_destinations(item, targets, depth + 1)),
      )
    PdfDictionary(entries) =>
      @syntax.PdfDictionary(
        entries.map(pair => {
          (pair.0, arrange_destinations(pair.1, targets, depth + 1))
        }),
      )
    PdfStreamObject(stream) =>
      @syntax.pdf_stream(
        arrange_destinations(stream.dictionary, targets, depth + 1),
        stream.data,
      )
    _ => value
  }
}

///|
fn PdfTransaction::arrange_destinations(
  self : PdfTransaction,
  targets : Map[Int32, Array[PdfArrangeTarget]],
) -> Unit raise {
  for (number, _, source) in self.session.document.parsed_object_entries() {
    let object = self.objects.get(number).unwrap_or(source)
    let updated = arrange_destinations(object, targets, 0)
    if updated != object {
      self.objects[number] = updated
    }
  }
}

///|
fn check_arranged_page_references(
  value : @syntax.PdfObject,
  pages : Map[Int32, Bool],
  allowed : Bool,
  depth : Int32,
) -> Unit raise {
  @pdfcore.sdk_check(1)
  @pdfcore.sdk_depth(depth)
  match value {
    PdfIndirect(number) => {
      guard allowed || !pages.contains(number) else {
        @failure.reject(
          "protected-content", "An unknown retained relationship refers to an arranged page",
        )
      }
    }
    PdfArray([PdfIndirect(_), PdfNameObject(mode), ..]) if [
        "XYZ", "Fit", "FitB", "FitH", "FitV", "FitBH", "FitBV", "FitR",
      ].any(key => mode == pdf_name(key)) => {
      guard value is PdfArray(items) else {
        abort("Expected destination array")
      }
      for item in items[1:] {
        check_arranged_page_references(item, pages, false, depth + 1)
      }
    }
    PdfArray(items) =>
      for item in items {
        check_arranged_page_references(item, pages, allowed, depth + 1)
      }
    PdfDictionary(entries) =>
      for (key, item) in entries {
        let pageTree = key == pdf_name("Kids") &&
          is_name(raw(value, "Type"), "Pages")
        let owner = key == pdf_name("P") &&
          [
            "Text", "Highlight", "Underline", "StrikeOut", "Ink", "Square", "Circle",
            "Line", "Stamp", "Widget", "Link",
          ].any(kind => is_name(raw(value, "Subtype"), kind))
        check_arranged_page_references(
          item,
          pages,
          pageTree || owner,
          depth + 1,
        )
      }
    PdfStreamObject(stream) =>
      check_arranged_page_references(stream.dictionary, pages, false, depth + 1)
    _ => ()
  }
}

///|
fn PdfTransaction::check_arranged_references(
  self : PdfTransaction,
  pages : Map[Int32, Bool],
) -> Unit raise {
  for number, _ in self.reachable_objects() {
    check_arranged_page_references(self.object(number), pages, false, 0)
  }
}
