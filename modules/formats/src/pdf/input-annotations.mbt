///|
fn annotation_refs(
  document : @pdflite.PdfDocument,
  page : @syntax.PdfObject,
) -> Array[@syntax.PdfObject] raise @failure.Failure {
  let value = get(document, page, "Annots")
  if value == @syntax.PdfNull {
    return []
  }
  guard value is PdfArray(items) && items.length() <= 4096 else {
    @failure.reject("limit-exceeded", "PDF annotation count exceeds budget")
  }
  items
}

///|
fn annotation_reason(
  object : @syntax.PdfObject,
) -> String raise @failure.Failure {
  if !is_name(raw(object, "Subtype"), "Text") &&
    !is_name(raw(object, "Subtype"), "Highlight") &&
    !is_name(raw(object, "Subtype"), "Underline") &&
    !is_name(raw(object, "Subtype"), "StrikeOut") &&
    !is_name(raw(object, "Subtype"), "Stamp") &&
    !drawing_annotation_kind(object) {
    return "Unsupported annotation type"
  }
  let flags = raw(object, "F")
  if flags != @syntax.PdfNull && (integer(flags) & (64 | 128 | 512)) != 0 {
    return "Locked PDF annotation"
  }
  for key in ["RC", "A", "AA", "StructParent", "State", "StateModel", "OC"] {
    if raw(object, key) != @syntax.PdfNull {
      return "Annotation relationship or content is protected: " + key
    }
  }
  if raw(object, "IRT") != @syntax.PdfNull &&
    !(raw(object, "IRT") is PdfIndirect(_)) {
    return "Direct annotation replies are protected"
  }
  if raw(object, "Popup") != @syntax.PdfNull &&
    !(raw(object, "Popup") is PdfIndirect(_)) {
    return "Direct annotation popup is protected"
  }
  if raw(object, "RT") != @syntax.PdfNull && !is_name(raw(object, "RT"), "R") {
    return "Unsupported annotation reply type"
  }
  if drawing_annotation_kind(object) {
    for
      key in [
        "IC", "RD", "BE", "Measure", "CL", "Path", "LL", "LLE", "LLO", "Cap",
      ] {
      if raw(object, key) != @syntax.PdfNull {
        return "Drawing annotation property is protected: " + key
      }
    }
    let endings = raw(object, "LE")
    if endings != @syntax.PdfNull &&
      endings != @syntax.PdfArray([tag("None"), tag("None")]) &&
      endings != @syntax.PdfArray([tag("None"), tag("OpenArrow")]) {
      return "Unsupported annotation line endings"
    }
  }
  if is_name(raw(object, "Subtype"), "Stamp") &&
    raw(object, "ODStampBase") == @syntax.PdfNull {
    return "Imported stamp appearance editing is protected"
  }
  ""
}

///|
fn check_pdf_text(text : String) -> Unit raise @failure.Failure {
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "PDF text exceeds budget")
  }
  let mut index = 0
  while index < text.length() {
    let value = text[index].to_int()
    if value >= 0xd800 && value <= 0xdbff {
      guard index + 1 < text.length() &&
        text[index + 1].to_int() >= 0xdc00 &&
        text[index + 1].to_int() <= 0xdfff else {
        @failure.reject("invalid-text", "Invalid UTF-16 surrogate")
      }
      index += 2
    } else {
      guard !(value >= 0xdc00 && value <= 0xdfff) else {
        @failure.reject("invalid-text", "Invalid UTF-16 surrogate")
      }
      index += 1
    }
  }
}

///|
fn pdf_string(text : String) -> @syntax.PdfObject {
  @syntax.PdfString(@utf16.encode(text, bom=true, endianness=Big))
}

///|
fn appearance_stream(
  bytes : Bytes,
  width : Double,
  height : Double,
  resources : @syntax.PdfObject,
) -> @syntax.PdfObject {
  stream(bytes, [
    ("Type", tag("XObject")),
    ("Subtype", tag("Form")),
    ("FormType", @syntax.PdfInteger(1)),
    (
      "BBox",
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfReal(width),
        @syntax.PdfReal(height),
      ]),
    ),
    ("Resources", resources),
  ])
}

///|
fn appearance_style(style : @layout.DrawStyle) -> @syntax.PdfObject {
  dict([
    (
      "ExtGState",
      dict([
        (
          "GS",
          dict([
            ("Type", tag("ExtGState")),
            ("ca", @syntax.PdfReal(style.fillAlpha)),
            ("CA", @syntax.PdfReal(style.strokeAlpha)),
            ("BM", tag(if style.multiply { "Multiply" } else { "Normal" })),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn annotation_appearance(
  tx : PdfTransaction,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise {
  if is_name(raw(object, "Subtype"), "Stamp") {
    return stamp_annotation_appearance(tx, object)
  }
  if drawing_annotation_kind(object) {
    return drawing_annotation_appearance(tx, object)
  }
  let (x, y, r, t) = rectangle(raw(object, "Rect"))
  let w = r - x
  let h = t - y
  let ops : Array[@content.PdfContentOp] = [@content.Op_q]
  let mut style = @layout.DrawStyle::default()
  if is_name(raw(object, "Subtype"), "Text") {
    let color = raw(object, "C")
    let color = if color == @syntax.PdfNull {
      [1.0, 0.85, 0.15]
    } else {
      guard color is PdfArray(items) && items.length() == 3 else {
        @failure.reject("protected-content", "Note color is unsupported")
      }
      items.map(number)
    }
    let alpha = raw(object, "CA")
    let alpha = if alpha == @syntax.PdfNull { 1.0 } else { number(alpha) }
    guard alpha >= 0 && alpha <= 1 else {
      @failure.reject("protected-content", "Note opacity is unsupported")
    }
    style = { ..style, fillAlpha: alpha, strokeAlpha: alpha, }
    ops.push(@content.Op_gs(pdf_name("GS")))
    ops.push(@content.Op_rg(color[0], color[1], color[2]))
    ops.push(@content.Op_re(0, 0, w, h))
    ops.push(@content.Op_f)
    ops.push(@content.Op_RG(0.35, 0.25, 0))
    let border = get(tx.session.document, raw(object, "BS"), "W")
    ops.push(
      @content.Op_w(
        if border == @syntax.PdfNull {
          w.min(h) / 16
        } else {
          number(border)
        },
      ),
    )
    for line in 1..<4 {
      let ly = h * line.to_double() / 4
      ops.push(@content.Op_m(w / 5, ly))
      ops.push(@content.Op_l(w * 4 / 5, ly))
    }
    ops.push(@content.Op_S)
  } else {
    guard raw(object, "QuadPoints") is PdfArray(points) &&
      points.length() > 0 &&
      points.length() % 8 == 0 &&
      points.length() / 8 <= 4096 else {
      @failure.reject(
        "protected-content", "Highlight has unsupported quadrilaterals",
      )
    }
    let color = raw(object, "C")
    let components = match color {
      PdfArray(items) if items.length() == 3 => items.map(number)
      PdfNull => [1.0, 1.0, 0.0]
      _ =>
        @failure.reject("protected-content", "Highlight color is unsupported")
    }
    let alpha = raw(object, "CA")
    let alpha = if alpha == @syntax.PdfNull { 1.0 } else { number(alpha) }
    guard alpha >= 0 && alpha <= 1 else {
      @failure.reject("invalid-pdf", "Invalid highlight opacity")
    }
    style = { ..style, fillAlpha: alpha, strokeAlpha: alpha, multiply: true, }
    ops.push(@content.Op_gs(pdf_name("GS")))
    ops.push(@content.Op_rg(components[0], components[1], components[2]))
    for offset in 0..<(points.length() / 8) {
      let q = points[offset * 8:offset * 8 + 8].map(number)
      if is_name(raw(object, "Subtype"), "Underline") ||
        is_name(raw(object, "Subtype"), "StrikeOut") {
        let ratio = if is_name(raw(object, "Subtype"), "Underline") {
          0.9
        } else {
          0.5
        }
        ops.push(@content.Op_RG(components[0], components[1], components[2]))
        let border = get(tx.session.document, raw(object, "BS"), "W")
        ops.push(
          @content.Op_w(
            if border == @syntax.PdfNull {
              1.0
            } else {
              number(border)
            },
          ),
        )
        ops.push(
          @content.Op_m(
            q[0] * (1 - ratio) + q[4] * ratio - x,
            q[1] * (1 - ratio) + q[5] * ratio - y,
          ),
        )
        ops.push(
          @content.Op_l(
            q[2] * (1 - ratio) + q[6] * ratio - x,
            q[3] * (1 - ratio) + q[7] * ratio - y,
          ),
        )
        ops.push(@content.Op_S)
        continue
      }
      ops.push(@content.Op_m(q[0] - x, q[1] - y))
      ops.push(@content.Op_l(q[2] - x, q[3] - y))
      ops.push(@content.Op_l(q[6] - x, q[7] - y))
      ops.push(@content.Op_l(q[4] - x, q[5] - y))
      ops.push(@content.Op_h)
    }
    ops.push(@content.Op_f)
  }
  ops.push(@content.Op_Q)
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
fn render_appearances(
  context : ContentContext,
  state : GraphicsState,
) -> Unit raise {
  let document = context.session.document
  let page = document.lookup_object_or_null(context.page.number)
  for index, reference in annotation_refs(document, page) {
    let object = resolve(document, reference)
    if is_name(raw(object, "Subtype"), "Popup") {
      continue
    }
    let flags = get(document, object, "F")
    if flags != @syntax.PdfNull && (integer(flags) & (1 | 2 | 32)) != 0 {
      continue
    }
    let before = context.commands.length()
    let nesting = context.nesting
    try {
      guard flags == @syntax.PdfNull || (integer(flags) & (8 | 16)) == 0 else {
        @failure.reject(
          "unsupported-pdf", "NoZoom and NoRotate annotation appearance is unsupported",
        )
      }
      guard raw(object, "OC") == @syntax.PdfNull else {
        @failure.reject(
          "unsupported-pdf", "Optional PDF annotation content is unsupported",
        )
      }
      let ap = get(document, object, "AP")
      if is_name(raw(object, "Subtype"), "Link") && ap == @syntax.PdfNull {
        let width = get(document, get(document, object, "BS"), "W")
        let border = get(document, object, "Border")
        if (width != @syntax.PdfNull && number(width) == 0) ||
          (
            width == @syntax.PdfNull &&
            border is PdfArray(items) &&
            items.length() >= 3 &&
            number(items[2]) == 0
          ) {
          continue
        }
      }
      let normal = get(document, ap, "N")
      let normal = if normal is PdfDictionary(_) {
        get(
          document,
          normal,
          match get(document, object, "AS") {
            PdfNameObject(name) =>
              @utf8.decode_lossy(name.bytes())[1:].to_owned()
            _ =>
              @failure.reject(
                "unsupported-pdf", "Annotation appearance requires a state",
              )
          },
        )
      } else {
        normal
      }
      guard normal is PdfStreamObject(_) else {
        @failure.reject(
          "unsupported-pdf", "Annotation has no supported normal appearance",
        )
      }
      guard raw(normal, "Group") == @syntax.PdfNull else {
        @failure.reject(
          "unsupported-pdf", "Annotation transparency groups are unsupported",
        )
      }
      let (x, y, r, t) = rectangle(get(document, object, "Rect"))
      let (bx, by, br, bt) = rectangle(get(document, normal, "BBox"))
      let own_matrix = pdf_object_matrix(get(document, normal, "Matrix"))
      let points = [(bx, by), (br, by), (br, bt), (bx, bt)].map(p => {
        own_matrix.point(p.0, p.1)
      })
      let minx = points.map(p => p.0).fold(init=10000000000.0, Double::min)
      let maxx = points.map(p => p.0).fold(init=-10000000000.0, Double::max)
      let miny = points.map(p => p.1).fold(init=10000000000.0, Double::min)
      let maxy = points.map(p => p.1).fold(init=-10000000000.0, Double::max)
      guard maxx > minx && maxy > miny else {
        @failure.reject("invalid-pdf", "Degenerate annotation appearance")
      }
      let sx = (r - x) / (maxx - minx)
      let sy = (t - y) / (maxy - miny)
      let placement : @layout.Matrix = {
        a: sx,
        b: 0,
        c: 0,
        d: sy,
        e: x - minx * sx,
        f: y - miny * sy,
      }
      let matrix = context.page.matrix.then(placement).then(own_matrix)
      context.scope(
        @layout.ClipPath(
          path_in(
            [
              @layout.Move(bx, by),
              @layout.Line(br, by),
              @layout.Line(br, bt),
              @layout.Line(bx, bt),
              @layout.Close,
            ],
            matrix,
          ),
          false,
        ),
      )
      let resources = get(document, normal, "Resources")
      interpret(
        context,
        stream_bytes(document, normal),
        if resources == @syntax.PdfNull {
          context.page.resources
        } else {
          resources
        },
        "\{context.page.id}:appearance:\{index}",
        { ..state, matrix, clips: 0, },
        0,
      )
      context.restore()
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => {
        while context.commands.length() > before {
          ignore(context.commands.pop())
        }
        context.nesting = nesting
        context.displayComplete = false
        context.diagnostics.push(message)
      }
      @pdfcore.PdfError::FlateOutputLimitExceeded(_) =>
        @failure.reject(
          "limit-exceeded", "PDF appearance stream exceeds budget",
        )
      _ => {
        while context.commands.length() > before {
          ignore(context.commands.pop())
        }
        context.nesting = nesting
        context.displayComplete = false
        context.diagnostics.push("Malformed PDF annotation appearance")
      }
    }
  }
}

///|
pub fn PdfSession::add_note(
  self : PdfSession,
  revision : Int32,
  page_id : String,
  x : Double,
  y : Double,
  text : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  check_pdf_text(text)
  let page = self.page(page_id)
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull else {
    @failure.reject(
      "protected-content", "Tagged PDF annotation structure is protected",
    )
  }
  guard x >= 0 && y >= 0 && x <= page.width - 20 && y <= page.height - 20 else {
    @failure.reject("invalid-position", "Note must fit within the PDF page")
  }
  let inverse = page.matrix.inverse()
  let points = [(x, y), (x + 20, y), (x + 20, y + 20), (x, y + 20)].map(p => {
    inverse.point(p.0, p.1)
  })
  let xs = points.map(p => p.0)
  let ys = points.map(p => p.1)
  let rect = @syntax.PdfArray([
    @syntax.PdfReal(xs.fold(init=10000000000.0, Double::min)),
    @syntax.PdfReal(ys.fold(init=10000000000.0, Double::min)),
    @syntax.PdfReal(xs.fold(init=-10000000000.0, Double::max)),
    @syntax.PdfReal(ys.fold(init=-10000000000.0, Double::max)),
  ])
  let object = dict([
    ("Type", tag("Annot")),
    ("Subtype", tag("Text")),
    ("Rect", rect),
    ("Contents", pdf_string(text)),
    ("Name", tag("Comment")),
    ("F", @syntax.PdfInteger(4)),
    ("P", @syntax.PdfIndirect(page.number)),
  ])
  let reference = tx.add(
    pdf_bound(self.budget, () => annotation_appearance(tx, object)),
  )
  let refs = annotation_refs(
    self.document,
    self.document.lookup_object_or_null(page.number),
  )
  guard refs.length() < 4096 else {
    @failure.reject("limit-exceeded", "PDF annotation count exceeds budget")
  }
  tx.objects[page.number] = tx
    .object(page.number)
    .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs + [reference]))
  tx.commit(self.current)
}

///|
pub fn PdfSession::add_highlight(
  self : PdfSession,
  revision : Int32,
  layout_id : Int32,
  kind~ : String = "Highlight",
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard ["Highlight", "Underline", "StrikeOut"].contains(kind) else {
    @failure.reject("invalid-operation", "Unknown PDF text markup")
  }
  let display = self.current_display(layout_id)
  let page = self.page(display.page)
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull else {
    @failure.reject(
      "protected-content", "Tagged PDF annotation structure is protected",
    )
  }
  let (a, b) = self.selection
  let spans = selected_spans(display, a.min(b), a.max(b))
  guard !spans.is_empty() &&
    spans.length() <= 4096 &&
    spans.all(span => span.mapped) else {
    @failure.reject(
      "invalid-selection", "Highlight requires bounded mapped PDF text",
    )
  }
  check_pdf_text(self.selected_text(layout_id))
  let inverse = page.matrix.inverse()
  let points : Array[@syntax.PdfObject] = []
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  for span in spans {
    for index in [1, 2, 0, 3] {
      let (x, y) = inverse.point(span.quad[index * 2], span.quad[index * 2 + 1])
      xs.push(x)
      ys.push(y)
      points.push(@syntax.PdfReal(x))
      points.push(@syntax.PdfReal(y))
    }
  }
  let rect = @syntax.PdfArray([
    @syntax.PdfReal(xs.fold(init=10000000000.0, Double::min)),
    @syntax.PdfReal(ys.fold(init=10000000000.0, Double::min)),
    @syntax.PdfReal(xs.fold(init=-10000000000.0, Double::max)),
    @syntax.PdfReal(ys.fold(init=-10000000000.0, Double::max)),
  ])
  let object = dict([
    ("Type", tag("Annot")),
    ("Subtype", tag(kind)),
    ("Rect", rect),
    ("QuadPoints", @syntax.PdfArray(points)),
    (
      "C",
      @syntax.PdfArray([
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(if kind == "Highlight" { 1 } else { 0 }),
        @syntax.PdfInteger(0),
      ]),
    ),
    ("CA", @syntax.PdfReal(if kind == "Highlight" { 0.35 } else { 1.0 })),
    ("Contents", pdf_string(self.selected_text(layout_id))),
    ("F", @syntax.PdfInteger(4)),
    ("P", @syntax.PdfIndirect(page.number)),
  ])
  let reference = tx.add(
    pdf_bound(self.budget, () => annotation_appearance(tx, object)),
  )
  let refs = annotation_refs(
    self.document,
    self.document.lookup_object_or_null(page.number),
  )
  guard refs.length() < 4096 else {
    @failure.reject("limit-exceeded", "PDF annotation count exceeds budget")
  }
  tx.objects[page.number] = tx
    .object(page.number)
    .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs + [reference]))
  tx.commit(self.current)
}

///|
pub fn PdfSession::change_annotation(
  self : PdfSession,
  revision : Int32,
  page_id : String,
  annotation : String,
  text : String,
  delete : Bool,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  check_pdf_text(text)
  let page = self.page(page_id)
  let refs = annotation_refs(
    self.document,
    self.document.lookup_object_or_null(page.number),
  )
  let mut target : Int32? = None
  for reference in refs {
    if reference is PdfIndirect(n) &&
      "\{n}:\{self.generations.get(n).unwrap_or(0)}" == annotation {
      target = Some(n)
    }
  }
  guard target is Some(n) else {
    @failure.reject("invalid-operation", "Unknown PDF annotation")
  }
  let object = resolve(self.document, @syntax.PdfIndirect(n))
  let reason = annotation_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  self.check_annotation_relationships(page, n)
  if delete {
    pdf_bound(self.budget, () => self.delete_annotation_members(tx, n, false))
  } else {
    let updated = tx
      .object(n)
      .with_entry(pdf_name("Contents"), pdf_string(text))
    tx.objects[n] = pdf_bound(self.budget, () => {
      annotation_appearance(tx, updated)
    })
  }
  tx.commit(self.current)
}
