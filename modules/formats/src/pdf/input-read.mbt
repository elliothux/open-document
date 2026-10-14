///|
fn pdf_name(value : String) -> @pdfcore.PdfName {
  @pdfcore.pdf_name_of_bytes(@utf8.encode("/" + value))
}

///|
fn raw(object : @syntax.PdfObject, key : String) -> @syntax.PdfObject {
  object.lookup_immediate(pdf_name(key)).unwrap_or(@syntax.PdfNull)
}

///|
fn @syntax.PdfObject::with_entry(
  self : @syntax.PdfObject,
  name : @pdfcore.PdfName,
  value : @syntax.PdfObject,
) -> @syntax.PdfObject raise @failure.Failure {
  self.add_dict_entry(name, value) catch {
    _ => @failure.reject("invalid-pdf", "PDF dictionary is required")
  }
}

///|
fn resolve(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise @failure.Failure {
  let seen : Map[Int, Bool] = Map([])
  let mut value = object
  while value is PdfIndirect(number) {
    guard seen.length() < 64 && !seen.contains(number) else {
      @failure.reject("invalid-pdf", "Cyclic or deep PDF reference")
    }
    seen[number] = true
    // All source and candidate references are checked before interpretation.
    value = document.lookup_object_or_null(number)
  }
  value
}

///|
fn get(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> @syntax.PdfObject raise @failure.Failure {
  resolve(document, raw(resolve(document, object), key))
}

///|
fn number(value : @syntax.PdfObject) -> Double raise @failure.Failure {
  let result = match value {
    PdfInteger(v) => v.to_double()
    PdfReal(v) | PdfExactReal(v) => v
    _ => @failure.reject("invalid-pdf", "PDF number is required")
  }
  guard !result.is_nan() && !result.is_inf() && result.abs() <= 1000000000 else {
    @failure.reject("invalid-pdf", "PDF number exceeds coordinate budget")
  }
  result
}

///|
fn integer(value : @syntax.PdfObject) -> Int raise @failure.Failure {
  let n = number(value)
  guard n.to_int().to_double() == n else {
    @failure.reject("invalid-pdf", "PDF integer is required")
  }
  n.to_int()
}

///|
fn is_name(value : @syntax.PdfObject, name : String) -> Bool {
  value == @syntax.PdfNameObject(pdf_name(name))
}

///|
fn rectangle(
  value : @syntax.PdfObject,
) -> (Double, Double, Double, Double) raise @failure.Failure {
  guard value is PdfArray([a, b, c, d]) else {
    @failure.reject("invalid-pdf", "PDF rectangle is required")
  }
  let (x, y, r, t) = (number(a), number(b), number(c), number(d))
  guard r > x && t > y else {
    @failure.reject("invalid-pdf", "PDF rectangle is empty")
  }
  (x, y, r, t)
}

///|
fn validate_value(
  numbers : Map[Int, Int],
  value : @syntax.PdfObject,
  depth : Int,
) -> Unit raise {
  @pdfcore.sdk_depth(depth)
  match value {
    PdfIndirect(n) => {
      guard numbers.contains(n) else {
        @failure.reject("invalid-pdf", "Dangling PDF reference")
      }
    }
    PdfArray(items) =>
      for item in items {
        validate_value(numbers, item, depth + 1)
      }
    PdfDictionary(entries) =>
      for (_, item) in entries {
        validate_value(numbers, item, depth + 1)
      }
    PdfStreamObject(stream) => {
      guard raw(stream.dictionary, "F") == @syntax.PdfNull else {
        @failure.reject(
          "unsupported-pdf", "External PDF streams are unsupported",
        )
      }
      validate_value(numbers, stream.dictionary, depth + 1)
    }
    PdfReal(_) | PdfExactReal(_) => ignore(number(value))
    _ => ()
  }
}

///|
fn read_pages(
  document : @pdflite.PdfDocument,
  generations : Map[Int, Int],
  budget : PdfBudget,
) -> Array[SourcePage] raise {
  let catalog = resolve(document, @syntax.PdfIndirect(document.root()))
  let pages : Array[SourcePage] = []
  let visited : Map[Int, Bool] = Map([])
  fn walk(
    reference : @syntax.PdfObject,
    inherited : Map[String, @syntax.PdfObject],
    depth : Int,
  ) -> Int raise {
    @pdfcore.sdk_depth(depth)
    guard reference is PdfIndirect(id) && !visited.contains(id) else {
      @failure.reject("invalid-pdf", "PDF page tree is cyclic or not indirect")
    }
    visited[id] = true
    let object = resolve(document, reference)
    guard object is PdfDictionary(_) else {
      @failure.reject("invalid-pdf", "Invalid PDF page dictionary")
    }
    let effective = inherited.copy()
    for key in ["Resources", "MediaBox", "CropBox", "Rotate"] {
      let value = get(document, object, key)
      if value != @syntax.PdfNull {
        effective[key] = value
      }
    }
    if is_name(raw(object, "Type"), "Pages") {
      guard get(document, object, "Kids") is PdfArray(kids) else {
        @failure.reject("invalid-pdf", "PDF page tree requires Kids")
      }
      let mut count = 0
      for child in kids {
        count += walk(child, effective, depth + 1)
      }
      guard integer(get(document, object, "Count")) == count else {
        @failure.reject(
          "invalid-pdf", "PDF page count does not match page tree",
        )
      }
      count
    } else {
      guard is_name(raw(object, "Type"), "Page") &&
        pages.length() < budget.pages else {
        @failure.reject(
          "limit-exceeded", "Invalid PDF page or page budget exceeded",
        )
      }
      let media = effective.get("MediaBox").unwrap_or(@syntax.PdfNull)
      let (mx, my, mr, mt) = rectangle(media)
      let crop = effective.get("CropBox").unwrap_or(media)
      let (cx, cy, cr, ct) = rectangle(crop)
      let (x, y, r, t) = (cx.max(mx), cy.max(my), cr.min(mr), ct.min(mt))
      guard r > x && t > y else {
        @failure.reject("invalid-pdf", "CropBox does not intersect MediaBox")
      }
      let angle = integer(
        effective.get("Rotate").unwrap_or(@syntax.PdfInteger(0)),
      )
      guard angle % 90 == 0 else {
        @failure.reject(
          "invalid-pdf", "PDF rotation must be a multiple of 90 degrees",
        )
      }
      let rotate = (angle % 360 + 360) % 360
      let user_unit = get(document, object, "UserUnit")
      let unit = if user_unit == @syntax.PdfNull {
        1.0
      } else {
        number(user_unit)
      }
      let w = (r - x) * unit
      let h = (t - y) * unit
      guard unit > 0 && unit <= 75000 && w <= 14400 && h <= 14400 else {
        @failure.reject("limit-exceeded", "PDF page dimensions exceed budget")
      }
      let matrix : @layout.Matrix = match rotate {
        0 => { a: unit, b: 0, c: 0, d: -unit, e: -x * unit, f: t * unit, }
        90 => { a: 0, b: unit, c: unit, d: 0, e: -y * unit, f: -x * unit, }
        180 => { a: -unit, b: 0, c: 0, d: unit, e: r * unit, f: -y * unit, }
        _ => { a: 0, b: -unit, c: -unit, d: 0, e: t * unit, f: r * unit, }
      }
      ignore(matrix.inverse())
      let generation = generations.get(id).unwrap_or(0)
      pages.push({
        number: id,
        generation,
        id: "\{id}:\{generation}",
        resources: effective
        .get("Resources")
        .unwrap_or(@syntax.PdfDictionary([])),
        media,
        crop,
        rotate,
        unit,
        width: if rotate % 180 == 0 {
          w
        } else {
          h
        },
        height: if rotate % 180 == 0 {
          h
        } else {
          w
        },
        matrix,
      })
      1
    }
  }
  ignore(walk(raw(catalog, "Pages"), Map([]), 0))
  guard !pages.is_empty() else {
    @failure.reject("invalid-pdf", "PDF has no pages")
  }
  pages
}

///|
/// Open the newest strict revision, keeping source objects separate from derived data.
pub fn PdfSession::open(
  bytes : Bytes,
  budget : PdfBudget,
) -> PdfSession raise @failure.Failure {
  let defaults = PdfBudget::default().to_json()
  guard budget.to_json() is Object(values) && defaults is Object(maxima) else {
    @failure.reject("invalid-budget", "Invalid PDF budget")
  }
  for key, value in values {
    guard value is Number(n, ..) &&
      maxima.get(key) is Some(Number(maximum, ..)) &&
      n > 0 &&
      n <= maximum else {
      @failure.reject(
        "invalid-budget",
        "PDF budget must be positive and bounded: " + key,
      )
    }
  }
  guard bytes.length() <= budget.fileBytes else {
    @failure.reject("limit-exceeded", "PDF input exceeds budget")
  }
  pdf_bound(budget, () => {
    let document = @pdflite.pdf_read_classic_document_from_view(bytes)
    let (major, minor) = document.version()
    guard major == 1 && minor >= 0 && minor <= 7 else {
      @failure.reject(
        "unsupported-pdf", "Only PDF 1.0 through 1.7 are supported",
      )
    }
    guard document.object_count() <= budget.objects else {
      @failure.reject("limit-exceeded", "PDF object budget exceeded")
    }
    let generations : Map[Int, Int] = Map([])
    let mut reason = ""
    let mut maximum = 0
    for (id, generation, value) in document.parsed_object_entries() {
      guard id > 0 && id <= budget.objectNumber else {
        @failure.reject("limit-exceeded", "PDF object number exceeds budget")
      }
      generations[id] = generation
      maximum = maximum.max(id)
      if generation != 0 {
        reason = "Nonzero object generations cannot be safely rewritten by the pinned writer"
      }
      if is_name(raw(value, "Type"), "Sig") ||
        is_name(raw(value, "FT"), "Sig") ||
        raw(value, "ByteRange") != @syntax.PdfNull {
        reason = "Signed PDF: signatures have not been verified; editing is protected"
      }
    }
    for (_, _, value) in document.parsed_object_entries() {
      validate_value(generations, value, 0)
    }
    let catalog = resolve(document, @syntax.PdfIndirect(document.root()))
    guard !is_name(raw(catalog, "Version"), "2.0") else {
      @failure.reject("unsupported-pdf", "PDF 2.0 is unsupported")
    }
    if raw(catalog, "Perms") != @syntax.PdfNull {
      reason = "Certified PDF is protected; signatures have not been verified"
    }
    guard raw(document.trailer_dict(), "Encrypt") == @syntax.PdfNull else {
      @failure.reject("unsupported-pdf", "Encrypted PDF is unsupported")
    }
    let pages = read_pages(document, generations, budget)
    {
      document,
      original: bytes,
      budget,
      generations,
      pages,
      revision: 0,
      layoutId: 0,
      display: None,
      current: pages[0].id,
      selection: (0, 0),
      nextObject: maximum + 1,
      stateId: 0,
      nextState: 1,
      undo: [],
      redo: [],
      historyBytes: 0,
      readOnlyReason: reason,
      closed: false,
    }
  })
}
