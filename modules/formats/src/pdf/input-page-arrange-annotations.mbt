///|
fn PdfTransaction::arrange_appearance(
  self : PdfTransaction,
  reference : @syntax.PdfObject,
  oldRect : @syntax.PdfObject,
  newRect : @syntax.PdfObject,
  transform : @layout.Matrix,
  depth : Int32,
) -> @syntax.PdfObject raise {
  guard depth < 8 else {
    @failure.reject(
      "protected-content", "Annotation appearance states are too deep",
    )
  }
  let object = resolve(self.session.document, reference)
  match object {
    PdfDictionary(states) => {
      guard states.length() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Annotation appearance states exceed budget",
        )
      }
      @syntax.PdfDictionary(
        states.map(pair => {
          (
            pair.0,
            self.arrange_appearance(
              pair.1,
              oldRect,
              newRect,
              transform,
              depth + 1,
            ),
          )
        }),
      )
    }
    PdfStreamObject(_) => {
      let box = get(self.session.document, object, "BBox")
      let own = pdf_object_matrix(get(self.session.document, object, "Matrix"))
      let (bx, by, br, bt) = rectangle(arrange_rect(box, own))
      let (x, y, r, t) = rectangle(oldRect)
      let (nx, ny, nr, nt) = rectangle(newRect)
      let sx = (r - x) / (br - bx)
      let sy = (t - y) / (bt - by)
      let placement : @layout.Matrix = {
        a: sx,
        b: 0,
        c: 0,
        d: sy,
        e: x - bx * sx,
        f: y - by * sy,
      }
      let translated : @layout.Matrix = {
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        e: -nx,
        f: -ny,
      }
      let matrix = translated.then(transform).then(placement)
      let resource = if reference is PdfIndirect(_) {
        reference
      } else {
        self.add(object.deep_copy())
      }
      self.add(
        appearance_stream(
          @pdflite.pdf_content_bytes_of_ops([
            @content.Op_q,
            @content.Op_cm(geometry_matrix(matrix)),
            @content.Op_Do(pdf_name("OriginalAppearance")),
            @content.Op_Q,
          ]),
          nr - nx,
          nt - ny,
          dict([("XObject", dict([("OriginalAppearance", resource)]))]),
        ),
      )
    }
    _ =>
      @failure.reject(
        "protected-content", "Annotation appearance cannot be transformed safely",
      )
  }
}

///|
fn PdfTransaction::arrange_annotation(
  self : PdfTransaction,
  reference : @syntax.PdfObject,
  destination : Int32,
  transform : @layout.Matrix,
) -> @syntax.PdfObject raise {
  guard reference is PdfIndirect(annotationNumber) else {
    @failure.reject(
      "protected-content", "Direct annotation cannot be rearranged safely",
    )
  }
  let mut annotation = self.object(annotationNumber)
  guard [
    "Text", "Highlight", "Underline", "StrikeOut", "Ink", "Square", "Circle", "Line",
    "Stamp", "Widget", "Link",
  ].any(kind => is_name(raw(annotation, "Subtype"), kind)) else {
    @failure.reject(
      "protected-content", "Unsupported annotation protects page arrangement",
    )
  }
  for
    key in [
      "IRT", "Popup", "OC", "StructParent", "Measure", "Path", "CL", "RD", "AA",
    ] {
    guard raw(annotation, key) == @syntax.PdfNull else {
      @failure.reject(
        "protected-content",
        "Annotation relationship or geometry is protected: " + key,
      )
    }
  }
  let flags = raw(annotation, "F")
  guard flags == @syntax.PdfNull ||
    (integer(flags) & (8 | 16 | 64 | 128 | 512)) == 0 else {
    @failure.reject(
      "protected-content", "Locked or fixed-view annotation cannot be rearranged",
    )
  }
  let oldRect = get(self.session.document, annotation, "Rect")
  let newRect = arrange_rect(oldRect, transform)
  let stampBase = raw(annotation, "ODStampBase")
  if stampBase != @syntax.PdfNull {
    annotation = annotation.with_entry(
      pdf_name("ODStampBase"),
      self.arrange_appearance(stampBase, oldRect, newRect, transform, 0),
    )
  }
  let ap = get(self.session.document, annotation, "AP")
  if ap != @syntax.PdfNull {
    guard ap is PdfDictionary(appearances) &&
      appearances.all(pair => {
        ["N", "R", "D"].any(key => pair.0 == pdf_name(key))
      }) else {
      @failure.reject(
        "protected-content", "Unsupported annotation appearance dictionary",
      )
    }
    let appearances = appearances.map(pair => {
      (
        pair.0,
        if pair.1 == @syntax.PdfNull && pair.0 != pdf_name("N") {
          pair.1
        } else {
          self.arrange_appearance(pair.1, oldRect, newRect, transform, 0)
        },
      )
    })
    annotation = annotation.with_entry(
      pdf_name("AP"),
      @syntax.PdfDictionary(appearances),
    )
  }
  annotation = annotation
    .with_entry(pdf_name("Rect"), newRect)
    .with_entry(pdf_name("P"), @syntax.PdfIndirect(destination))
  for key in ["QuadPoints", "Vertices", "L"] {
    let points = get(self.session.document, annotation, key)
    if points != @syntax.PdfNull {
      annotation = annotation.with_entry(
        pdf_name(key),
        transform_pdf_points(points, transform),
      )
    }
  }
  let ink = get(self.session.document, annotation, "InkList")
  if ink is PdfArray(strokes) {
    annotation = annotation.with_entry(
      pdf_name("InkList"),
      @syntax.PdfArray(
        strokes.map(stroke => transform_pdf_points(stroke, transform)),
      ),
    )
  }
  let scale = (transform.a * transform.a + transform.b * transform.b).sqrt()
  let bs = get(self.session.document, annotation, "BS")
  let border = get(self.session.document, annotation, "Border")
  if bs != @syntax.PdfNull || border == @syntax.PdfNull {
    let mut bs = if bs == @syntax.PdfNull { dict([]) } else { bs }
    let originalWidth = get(self.session.document, bs, "W")
    bs = bs.with_entry(
      pdf_name("W"),
      @syntax.PdfReal(
        (if originalWidth == @syntax.PdfNull {
          1.0
        } else {
          number(originalWidth)
        }) *
        scale,
      ),
    )
    let dash = get(self.session.document, bs, "D")
    if dash != @syntax.PdfNull {
      guard dash is PdfArray(items) else {
        @failure.reject(
          "protected-content", "Annotation border dash is malformed",
        )
      }
      bs = bs.with_entry(
        pdf_name("D"),
        @syntax.PdfArray(
          items.map(value => @syntax.PdfReal(number(value) * scale)),
        ),
      )
    }
    annotation = annotation.with_entry(pdf_name("BS"), bs)
  }
  if border != @syntax.PdfNull {
    guard border is PdfArray(items) &&
      (items.length() == 3 || items.length() == 4) else {
      @failure.reject("protected-content", "Annotation border is malformed")
    }
    let scaled = [
      @syntax.PdfReal(number(items[0]) * scale),
      @syntax.PdfReal(number(items[1]) * scale),
      @syntax.PdfReal(number(items[2]) * scale),
    ]
    if items.length() == 4 {
      guard items[3] is PdfArray(dash) else {
        @failure.reject(
          "protected-content", "Annotation border dash is malformed",
        )
      }
      scaled.push(
        @syntax.PdfArray(
          dash.map(value => @syntax.PdfReal(number(value) * scale)),
        ),
      )
    }
    annotation = annotation.with_entry(
      pdf_name("Border"),
      @syntax.PdfArray(scaled),
    )
  }
  self.objects[annotationNumber] = annotation
  reference
}

///|
fn PdfTransaction::arrange_fields(
  self : PdfTransaction,
  targets : Map[Int32, Array[PdfArrangeTarget]],
) -> Unit raise {
  for field in self.session.fields() {
    let chosen = field.widgets.filter(widget => {
      targets.contains(self.session.page(widget.1).number)
    })
    if chosen.is_empty() {
      continue
    }
    guard chosen.length() == field.widgets.length() &&
      (field.reason.is_empty() || field.reason == "Read-only PDF field") else {
      @failure.reject(
        "protected-content", "A field spans unselected pages or has protected relationships",
      )
    }
    let first = self.session.page(chosen[0].1)
    let firstMatrix = targets[first.number][0].matrix
    let scale = (firstMatrix.a * firstMatrix.a + firstMatrix.b * firstMatrix.b).sqrt()
    for (number, id) in chosen {
      let page = self.session.page(id)
      let matrix = targets[page.number][0].matrix
      let current = (matrix.a * matrix.a + matrix.b * matrix.b).sqrt()
      guard page.rotate == 0 && (current - scale).abs() < 0.000001 else {
        @failure.reject(
          "protected-content", "Widgets need a common scale on unrotated pages",
        )
      }
      let mk = get(
        self.session.document,
        self.session.document.lookup_object_or_null(number),
        "MK",
      )
      if mk is PdfDictionary(entries) {
        guard entries.all(pair => {
          ["BC", "BG"].any(key => pair.0 == pdf_name(key)) ||
          (
            pair.0 == pdf_name("R") &&
            integer(resolve(self.session.document, pair.1)) == 0
          )
        }) else {
          @failure.reject(
            "protected-content", "Widget icon or rotation needs explicit reconstruction",
          )
        }
      }
    }
    if ["text", "choice", "list"].contains(field.kind) {
      guard field.attributes.get("DA") is Some(PdfString(bytes)) else {
        @failure.reject(
          "protected-content", "Field needs a default appearance to preserve its scale",
        )
      }
      let ops = @pdflite.pdf_parse_content_ops_from_view(bytes).map(op => {
        match op {
          Op_Tf(name, size) => {
            guard size >= 0 && size * scale <= 14400 else {
              @failure.reject(
                "protected-content", "Arranged field font size exceeds the editable geometry budget",
              )
            }
            @content.Op_Tf(name, size * scale)
          }
          Op_g(_) | Op_rg(_, _, _) => op
          _ =>
            @failure.reject(
              "protected-content", "Field default appearance is unsupported",
            )
        }
      })
      self.objects[field.number] = self
        .object(field.number)
        .with_entry(
          pdf_name("DA"),
          @syntax.PdfString(@pdflite.pdf_content_bytes_of_ops(ops)),
        )
    }
  }
}
