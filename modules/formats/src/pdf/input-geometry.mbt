///|
fn pdf_rectangle(
  x : Double,
  y : Double,
  r : Double,
  t : Double,
) -> @syntax.PdfObject {
  @syntax.PdfArray([
    @syntax.PdfReal(x),
    @syntax.PdfReal(y),
    @syntax.PdfReal(r),
    @syntax.PdfReal(t),
  ])
}

///|
pub fn PdfSession::crop_page(
  self : PdfSession,
  revision : Int32,
  id : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  guard x >= 0 &&
    y >= 0 &&
    width > 0 &&
    height > 0 &&
    x + width <= page.width &&
    y + height <= page.height else {
    @failure.reject(
      "invalid-page", "PDF crop must be a nonempty rectangle inside the displayed page",
    )
  }
  let inverse = page.matrix.inverse()
  let (a, b) = inverse.point(x, y)
  let (c, d) = inverse.point(x + width, y + height)
  tx.objects[page.number] = tx
    .object(page.number)
    .with_entry(
      pdf_name("CropBox"),
      pdf_rectangle(a.min(c), b.min(d), a.max(c), b.max(d)),
    )
  tx.commit(self.current)
}

///|
fn transform_pdf_points(
  value : @syntax.PdfObject,
  matrix : @layout.Matrix,
) -> @syntax.PdfObject raise @failure.Failure {
  guard value is PdfArray(points) &&
    points.length() % 2 == 0 &&
    points.length() <= 32768 else {
    @failure.reject("protected-content", "Unsupported annotation coordinates")
  }
  let output : Array[@syntax.PdfObject] = []
  for i = 0; i < points.length(); i = i + 2 {
    let (x, y) = matrix.point(number(points[i]), number(points[i + 1]))
    output.push(@syntax.PdfReal(x))
    output.push(@syntax.PdfReal(y))
  }
  @syntax.PdfArray(output)
}

///|
fn transform_pdf_destinations(
  value : @syntax.PdfObject,
  page : Int32,
  matrix : @layout.Matrix,
  depth : Int32,
) -> @syntax.PdfObject raise {
  @pdfcore.sdk_depth(depth)
  match value {
    PdfArray([PdfIndirect(target), PdfNameObject(mode), ..]) if target == page => {
      let mode = @utf8.decode_lossy(mode.bytes())
      guard value is PdfArray(items) else { abort("Expected destination") }
      let output = items.copy()
      if mode == "/XYZ" && items.length() == 5 {
        if items[2] != @syntax.PdfNull {
          output[2] = @syntax.PdfReal(matrix.a * number(items[2]) + matrix.e)
        }
        if items[3] != @syntax.PdfNull {
          output[3] = @syntax.PdfReal(matrix.d * number(items[3]) + matrix.f)
        }
      } else if ["/FitH", "/FitBH"].contains(mode) && items.length() == 3 {
        if items[2] != @syntax.PdfNull {
          output[2] = @syntax.PdfReal(matrix.d * number(items[2]) + matrix.f)
        }
      } else if ["/FitV", "/FitBV"].contains(mode) && items.length() == 3 {
        if items[2] != @syntax.PdfNull {
          output[2] = @syntax.PdfReal(matrix.a * number(items[2]) + matrix.e)
        }
      } else if mode == "/FitR" && items.length() == 6 {
        let (x, y) = matrix.point(number(items[2]), number(items[3]))
        let (r, t) = matrix.point(number(items[4]), number(items[5]))
        output[2] = @syntax.PdfReal(x.min(r))
        output[3] = @syntax.PdfReal(y.min(t))
        output[4] = @syntax.PdfReal(x.max(r))
        output[5] = @syntax.PdfReal(y.max(t))
      } else if !(["/Fit", "/FitB"].contains(mode) && items.length() == 2) {
        @failure.reject(
          "protected-content", "PDF destination cannot be transformed safely",
        )
      }
      @syntax.PdfArray(output)
    }
    PdfArray(items) =>
      @syntax.PdfArray(
        items.map(item => {
          transform_pdf_destinations(item, page, matrix, depth + 1)
        }),
      )
    PdfDictionary(entries) =>
      @syntax.PdfDictionary(
        entries.map(pair => {
          (pair.0, transform_pdf_destinations(pair.1, page, matrix, depth + 1))
        }),
      )
    PdfStreamObject(s) =>
      @syntax.pdf_stream(
        transform_pdf_destinations(s.dictionary, page, matrix, depth + 1),
        s.data,
      )
    _ => value
  }
}

///|
pub fn PdfSession::resize_page(
  self : PdfSession,
  revision : Int32,
  id : String,
  width : Double,
  height : Double,
  scale : Bool,
  anchor : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  let reason = self.page_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard width > 0 &&
    height > 0 &&
    width <= 14400 &&
    height <= 14400 &&
    ["top-left", "center"].contains(anchor) else {
    @failure.reject(
      "invalid-page", "PDF size requires bounded dimensions and an explicit anchor",
    )
  }
  pdf_bound(self.budget, () => {
    let swapped = page.rotate == 90 || page.rotate == 270
    let box = pdf_rectangle(
      0,
      0,
      if swapped {
        height
      } else {
        width
      },
      if swapped {
        width
      } else {
        height
      },
    )
    let object = tx
      .object(page.number)
      .with_entry(pdf_name("MediaBox"), box)
      .with_entry(pdf_name("CropBox"), box)
      .with_entry(pdf_name("Rotate"), @syntax.PdfInteger(page.rotate))
      .with_entry(pdf_name("UserUnit"), @syntax.PdfInteger(1))
    let view = document_view(self.document)
    view.add_object_given_number(page.number, object)
    let resized = read_pages(view, self.generations, self.budget).filter(item => {
        item.id == id
      })[0]
    let sx = if scale { width / page.width } else { 1.0 }
    let sy = if scale { height / page.height } else { 1.0 }
    let screen : @layout.Matrix = {
      a: sx,
      b: 0,
      c: 0,
      d: sy,
      e: if anchor == "center" {
        (width - page.width * sx) / 2
      } else {
        0
      },
      f: if anchor == "center" {
        (height - page.height * sy) / 2
      } else {
        0
      },
    }
    let matrix = resized.matrix.inverse().then(screen).then(page.matrix)
    ignore(matrix.inverse())
    let (mx, my, mr, mt) = rectangle(page.media)
    let (cx, cy, cr, ct) = rectangle(page.crop)
    let prefix = @pdflite.pdf_content_bytes_of_ops([
      @content.Op_q,
      @content.Op_cm(geometry_matrix(matrix)),
      @content.Op_re(
        mx.max(cx),
        my.max(cy),
        mr.min(cr) - mx.max(cx),
        mt.min(ct) - my.max(cy),
      ),
      @content.Op_W,
      @content.Op_n,
    ])
    let bytes = content_bytes(
      self.document,
      raw(tx.object(page.number), "Contents"),
    )
    let suffix = b"\nQ\n"
    let joined = Bytes::makei(
      prefix.length() + bytes.length() + suffix.length(),
      i => {
        if i < prefix.length() {
          prefix[i]
        } else if i - prefix.length() < bytes.length() {
          bytes[i - prefix.length()]
        } else {
          suffix[i - prefix.length() - bytes.length()]
        }
      },
    )
    let contents = tx.add(stream(joined, []))
    tx.objects[page.number] = object
      .with_entry(pdf_name("Resources"), page.resources)
      .with_entry(pdf_name("Contents"), contents)
    for reference in annotation_refs(self.document, tx.object(page.number)) {
      guard reference is PdfIndirect(number) else {
        @failure.reject(
          "protected-content", "Direct annotation cannot be transformed safely",
        )
      }
      let mut annotation = tx.object(number)
      for key in ["Measure", "Path", "CL", "RD"] {
        guard raw(annotation, key) == @syntax.PdfNull else {
          @failure.reject(
            "protected-content",
            "Annotation geometry is protected: " + key,
          )
        }
      }
      let (x, y, r, t) = rectangle(get(self.document, annotation, "Rect"))
      let (a, b) = matrix.point(x, y)
      let (c, d) = matrix.point(r, t)
      annotation = annotation.with_entry(
        pdf_name("Rect"),
        pdf_rectangle(a.min(c), b.min(d), a.max(c), b.max(d)),
      )
      for key in ["QuadPoints", "Vertices", "L"] {
        let points = get(self.document, annotation, key)
        if points != @syntax.PdfNull {
          annotation = annotation.with_entry(
            pdf_name(key),
            transform_pdf_points(points, matrix),
          )
        }
      }
      if get(self.document, annotation, "InkList") is PdfArray(strokes) {
        annotation = annotation.with_entry(
          pdf_name("InkList"),
          @syntax.PdfArray(
            strokes.map(points => transform_pdf_points(points, matrix)),
          ),
        )
      }
      tx.objects[number] = annotation
    }
    for (number, _, original) in self.document.parsed_object_entries() {
      let value = tx.objects.get(number).unwrap_or(original)
      let transformed = transform_pdf_destinations(
        value,
        page.number,
        matrix,
        0,
      )
      if transformed != value {
        tx.objects[number] = transformed
      }
    }
    tx.commit(self.current)
  })
}
