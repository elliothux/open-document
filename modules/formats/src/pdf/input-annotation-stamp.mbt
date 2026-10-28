///|
fn stamp_annotation_appearance(
  tx : PdfTransaction,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise {
  guard raw(object, "ODStampBase") is PdfIndirect(n) &&
    tx.object(n) is PdfStreamObject(base) else {
    @failure.reject(
      "protected-content", "Stamp appearance cannot be isolated safely",
    )
  }
  let (x, y, r, t) = rectangle(raw(base.dictionary, "BBox"))
  let (ax, ay, ar, at) = rectangle(raw(object, "Rect"))
  let width = ar - ax
  let height = at - ay
  let alpha = raw(object, "CA")
  let alpha = if alpha == @syntax.PdfNull { 1.0 } else { number(alpha) }
  guard alpha >= 0 && alpha <= 1 else {
    @failure.reject("invalid-operation", "Stamp opacity is invalid")
  }
  let resources = appearance_style({
    ..@layout.DrawStyle::default(),
    fillAlpha: alpha,
    strokeAlpha: alpha,
  }).with_entry(pdf_name("XObject"), dict([("Stamp", @syntax.PdfIndirect(n))]))
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_gs(pdf_name("GS")),
    @content.Op_q,
    @content.Op_cm({
      a: width / (r - x),
      b: 0,
      c: 0,
      d: height / (t - y),
      e: -x * width / (r - x),
      f: -y * height / (t - y),
    }),
    @content.Op_Do(pdf_name("Stamp")),
    @content.Op_Q,
  ]
  let border = get(tx.session.document, raw(object, "BS"), "W")
  let border = if border == @syntax.PdfNull { 0.0 } else { number(border) }
  guard border >= 0 && border <= 100 else {
    @failure.reject("invalid-operation", "Stamp border is invalid")
  }
  if border > 0 {
    guard raw(object, "C") is PdfArray([red, green, blue]) else {
      @failure.reject("protected-content", "Stamp border color is unsupported")
    }
    ops.append([
      @content.Op_RG(number(red), number(green), number(blue)),
      @content.Op_w(border),
      @content.Op_re(
        border / 2,
        border / 2,
        (width - border).max(0),
        (height - border).max(0),
      ),
      @content.Op_S,
    ])
  }
  ops.push(@content.Op_Q)
  let appearance = tx.add(
    appearance_stream(
      @pdflite.pdf_content_bytes_of_ops(ops),
      width,
      height,
      resources,
    ),
  )
  object.with_entry(pdf_name("AP"), dict([("N", appearance)]))
}

///|
/// A visual stamp/signature is an image annotation, never a cryptographic Sig field.
pub fn PdfSession::add_stamp_annotation(
  self : PdfSession,
  revision : Int32,
  id : String,
  style : PdfAnnotationStyle,
  width : Int32,
  height : Int32,
  rgba : Bytes,
  signature : Bool,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  check_annotation_style(page, style)
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
    let base = tx.image_form(width, height, rgba)
    let p = style.placement
    let (a, b) = page.matrix.inverse().point(p.x, p.y)
    let (c, d) = page.matrix.inverse().point(p.x + p.width, p.y + p.height)
    let object = dict([
      ("Type", tag("Annot")),
      ("Subtype", tag("Stamp")),
      ("Name", tag(if signature { "Signature" } else { "Stamp" })),
      ("ODSignature", @syntax.PdfBoolean(signature)),
      ("ODStampBase", base),
      ("Rect", pdf_rectangle(a.min(c), b.min(d), a.max(c), b.max(d))),
      ("P", @syntax.PdfIndirect(page.number)),
      ("F", @syntax.PdfInteger(4)),
      ("CA", @syntax.PdfReal(style.opacity)),
      ("BS", dict([("W", @syntax.PdfReal(style.border)), ("S", tag("S"))])),
      (
        "C",
        @syntax.PdfArray(
          [0, 2, 4].map(i => @syntax.PdfReal(channel(style.color, i))),
        ),
      ),
      ("T", pdf_string(style.author)),
      ("Contents", pdf_string(style.text)),
    ])
    let reference = tx.add(stamp_annotation_appearance(tx, object))
    let refs = annotation_refs(self.document, tx.object(page.number))
    guard refs.length() < 4096 else {
      @failure.reject("limit-exceeded", "PDF stamps exceed annotation budget")
    }
    tx.objects[page.number] = tx
      .object(page.number)
      .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs + [reference]))
    tx.commit(self.current)
  })
}
