///|
fn drawing_annotation_kind(object : @syntax.PdfObject) -> Bool {
  ["Square", "Circle", "Line", "Ink"].any(kind => {
    is_name(raw(object, "Subtype"), kind)
  })
}

///|
fn drawing_annotation_appearance(
  tx : PdfTransaction,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise {
  let (x, y, r, t) = rectangle(raw(object, "Rect"))
  let w = r - x
  let h = t - y
  let color = raw(object, "C")
  guard color is PdfArray([red, green, blue]) else {
    @failure.reject(
      "protected-content", "Drawing annotation requires RGB color",
    )
  }
  let alpha = raw(object, "CA")
  let alpha = if alpha == @syntax.PdfNull { 1.0 } else { number(alpha) }
  let border = get(tx.session.document, raw(object, "BS"), "W")
  let border = if border == @syntax.PdfNull { 1.0 } else { number(border) }
  guard alpha >= 0 &&
    alpha <= 1 &&
    border >= 0 &&
    border <= 100 &&
    [red, green, blue].all(value => number(value) >= 0 && number(value) <= 1) else {
    @failure.reject(
      "protected-content", "Drawing annotation style is unsupported",
    )
  }
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_gs(pdf_name("GS")),
    @content.Op_RG(number(red), number(green), number(blue)),
    @content.Op_w(border),
  ]
  if is_name(raw(object, "Subtype"), "Ink") {
    ops.append([@content.Op_J(1), @content.Op_j(1)])
  }
  if is_name(raw(object, "Subtype"), "Square") {
    ops.push(
      @content.Op_re(
        border / 2,
        border / 2,
        (w - border).max(0),
        (h - border).max(0),
      ),
    )
  } else if is_name(raw(object, "Subtype"), "Circle") {
    let rx = (w - border).max(0) / 2
    let ry = (h - border).max(0) / 2
    let cx = w / 2
    let cy = h / 2
    let k = 0.5522847498307936
    ops.append([
      @content.Op_m(cx + rx, cy),
      @content.Op_c(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry),
      @content.Op_c(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy),
      @content.Op_c(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry),
      @content.Op_c(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy),
      @content.Op_h,
    ])
  } else {
    let paths = if is_name(raw(object, "Subtype"), "Line") {
      [raw(object, "L")]
    } else {
      guard raw(object, "InkList") is PdfArray(paths) else {
        @failure.reject("protected-content", "Ink annotation requires strokes")
      }
      paths
    }
    for path in paths {
      guard path is PdfArray(points) &&
        points.length() >= 4 &&
        points.length() % 2 == 0 &&
        points.length() <= 32768 else {
        @failure.reject(
          "protected-content", "Annotation stroke coordinates are unsupported",
        )
      }
      ops.push(@content.Op_m(number(points[0]) - x, number(points[1]) - y))
      for i = 2; i < points.length(); i = i + 2 {
        ops.push(
          @content.Op_l(number(points[i]) - x, number(points[i + 1]) - y),
        )
      }
      if is_name(raw(object, "Subtype"), "Line") &&
        raw(object, "LE") == @syntax.PdfArray([tag("None"), tag("OpenArrow")]) {
        let ax = number(points[points.length() - 2]) - x
        let ay = number(points[points.length() - 1]) - y
        let angle = @math.atan2(
          ay - (number(points[1]) - y),
          ax - (number(points[0]) - x),
        )
        let length = (border * 4).max(6).min(w.min(h) / 2)
        for turn in [-0.45, 0.45] {
          ops.push(
            @content.Op_m(
              ax - @math.cos(angle + turn) * length,
              ay - @math.sin(angle + turn) * length,
            ),
          )
          ops.push(@content.Op_l(ax, ay))
        }
      }
    }
  }
  ops.append([@content.Op_S, @content.Op_Q])
  let style : @layout.DrawStyle = {
    ..@layout.DrawStyle::default(),
    fillAlpha: alpha,
    strokeAlpha: alpha,
  }
  let appearance = tx.add(
    appearance_stream(
      @pdflite.pdf_content_bytes_of_ops(ops),
      w,
      h,
      appearance_style(style),
    ),
  )
  object.with_entry(pdf_name("AP"), dict([("N", appearance)]))
}

///|
pub(all) struct PdfDrawingAnnotation {
  kind : String
  placement : PdfPlacement
  points : Array[Double]
  color : String
  opacity : Double
  border : Double
  author : String
  text : String
  arrow : Bool
}

///|
pub fn PdfSession::add_drawing_annotation(
  self : PdfSession,
  revision : Int32,
  id : String,
  spec : PdfDrawingAnnotation,
  strokes~ : Array[Array[Double]] = [],
  signature~ : Bool = false,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  check_pdf_placement(spec.placement)
  check_pdf_text(spec.author)
  check_pdf_text(spec.text)
  guard ["Square", "Circle", "Line", "Ink"].contains(spec.kind) &&
    (!signature || spec.kind == "Ink") &&
    spec.placement.rotation == 0 &&
    spec.placement.x >= 0 &&
    spec.placement.y >= 0 &&
    spec.placement.x + spec.placement.width <= page.width &&
    spec.placement.y + spec.placement.height <= page.height &&
    spec.color.length() == 6 &&
    spec.color.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string())) &&
    spec.opacity >= 0 &&
    spec.opacity <= 1 &&
    spec.border >= 0 &&
    spec.border <= 100 else {
    @failure.reject(
      "invalid-operation", "Drawing annotation geometry or style is invalid",
    )
  }
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull else {
    @failure.reject(
      "protected-content", "Tagged annotation structure is protected",
    )
  }
  pdf_bound(self.budget, () => {
    let inverse = page.matrix.inverse()
    let p = spec.placement
    let (x, y) = inverse.point(p.x, p.y)
    let (r, t) = inverse.point(p.x + p.width, p.y + p.height)
    let components = [0, 2, 4].map(i => @syntax.PdfReal(channel(spec.color, i)))
    let mut object = dict([
      ("Type", tag("Annot")),
      ("Subtype", tag(spec.kind)),
      ("Rect", pdf_rectangle(x.min(r), y.min(t), x.max(r), y.max(t))),
      ("C", @syntax.PdfArray(components)),
      ("CA", @syntax.PdfReal(spec.opacity)),
      ("BS", dict([("W", @syntax.PdfReal(spec.border)), ("S", tag("S"))])),
      ("Contents", pdf_string(spec.text)),
      ("T", pdf_string(spec.author)),
      ("P", @syntax.PdfIndirect(page.number)),
      ("F", @syntax.PdfInteger(4)),
      ("ODSignature", @syntax.PdfBoolean(signature)),
    ])
    if spec.kind == "Line" || spec.kind == "Ink" {
      let paths = if spec.kind == "Ink" && !strokes.is_empty() {
        strokes
      } else {
        [spec.points]
      }
      guard paths.length() <= 4096 else {
        @failure.reject("limit-exceeded", "Ink stroke count exceeds budget")
      }
      let output : Array[@syntax.PdfObject] = []
      let mut units = 0
      for path in paths {
        guard path.length() >= 4 &&
          path.length() % 2 == 0 &&
          path.length() <= 32768 - units &&
          (spec.kind != "Line" || path.length() == 4) else {
          @failure.reject(
            "invalid-operation", "Bounded line or ink coordinates are required",
          )
        }
        units += path.length()
        let points : Array[@syntax.PdfObject] = []
        for i = 0; i < path.length(); i = i + 2 {
          let px = path[i]
          let py = path[i + 1]
          guard px >= p.x &&
            px <= p.x + p.width &&
            py >= p.y &&
            py <= p.y + p.height else {
            @failure.reject(
              "invalid-position", "Annotation stroke must fit its rectangle",
            )
          }
          let (a, b) = inverse.point(px, py)
          points.append([@syntax.PdfReal(a), @syntax.PdfReal(b)])
        }
        output.push(@syntax.PdfArray(points))
      }
      object = if spec.kind == "Line" {
        object
        .with_entry(pdf_name("L"), output[0])
        .with_entry(
          pdf_name("LE"),
          @syntax.PdfArray([
            tag("None"),
            tag(if spec.arrow { "OpenArrow" } else { "None" }),
          ]),
        )
      } else {
        object.with_entry(pdf_name("InkList"), @syntax.PdfArray(output))
      }
    }
    let reference = tx.add(drawing_annotation_appearance(tx, object))
    let refs = annotation_refs(self.document, tx.object(page.number))
    guard refs.length() < 4096 else {
      @failure.reject("limit-exceeded", "PDF annotations exceed budget")
    }
    tx.objects[page.number] = tx
      .object(page.number)
      .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs + [reference]))
    tx.commit(self.current)
  })
}
