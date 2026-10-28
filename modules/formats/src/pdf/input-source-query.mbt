///|
fn source_placement(
  session : PdfSession,
  target : PdfSourceObject,
) -> PdfPlacement raise @failure.Failure {
  if target.kind == "text" {
    guard !target.spans.is_empty() else {
      @failure.reject("protected-content", "PDF text has no measurable glyphs")
    }
    let basis = target.matrix.then(matrix(target.before.text_matrix))
    let angle = @math.atan2(basis.b, basis.a)
    let c = @math.cos(angle)
    let s = @math.sin(angle)
    let mut lowX = 1000000000.0
    let mut lowY = 1000000000.0
    let mut highX = -1000000000.0
    let mut highY = -1000000000.0
    for span in target.spans {
      for i in 0..<4 {
        let x = span.quad[i * 2]
        let y = span.quad[i * 2 + 1]
        let u = c * x + s * y
        let v = -s * x + c * y
        lowX = lowX.min(u)
        highX = highX.max(u)
        lowY = lowY.min(v)
        highY = highY.max(v)
      }
    }
    let result : PdfPlacement = {
      x: c * lowX - s * lowY,
      y: s * lowX + c * lowY,
      width: highX - lowX,
      height: highY - lowY,
      rotation: angle * 180 / 3.141592653589793,
    }
    check_pdf_placement(result)
    return result
  }
  let (x, y, r, t) = if target.kind.has_suffix("-form") {
    source_logical_box(session.document, target.reference)
  } else {
    (0.0, 0.0, 1.0, 1.0)
  }
  let mapping = target.matrix.then({
    a: r - x,
    b: 0,
    c: 0,
    d: y - t,
    e: x,
    f: t,
  })
  placement_from_matrix(mapping)
}

///|
fn placement_from_matrix(
  mapping : @layout.Matrix,
) -> PdfPlacement raise @failure.Failure {
  let width = (mapping.a * mapping.a + mapping.b * mapping.b).sqrt()
  let height = (mapping.c * mapping.c + mapping.d * mapping.d).sqrt()
  guard width > 0 &&
    height > 0 &&
    mapping.a * mapping.d - mapping.b * mapping.c > 0 &&
    (mapping.a * mapping.c + mapping.b * mapping.d).abs() <=
    width * height * 0.000001 else {
    @failure.reject(
      "protected-content", "Skewed or mirrored PDF object requires explicit reconstruction",
    )
  }
  let result : PdfPlacement = {
    x: mapping.e,
    y: mapping.f,
    width,
    height,
    rotation: @math.atan2(mapping.b, mapping.a) * 180 / 3.141592653589793,
  }
  check_pdf_placement(result)
  result
}

///|
fn source_text(display : PageDisplay, target : PdfSourceObject) -> String {
  if target.spans.is_empty() {
    return ""
  }
  let start = target.spans
    .iter()
    .fold(init=display.text.length(), (a, span) => a.min(span.start))
  let end = target.spans.iter().fold(init=0, (a, span) => a.max(span.end))
  if start <= end && end <= display.text.length() {
    display.text[start:end].to_owned()
  } else {
    ""
  }
}

///|
fn source_font_size(
  session : PdfSession,
  target : PdfSourceObject,
) -> Double raise @failure.Failure {
  let size = if target.kind == "text" {
    let basis = target.matrix.then(matrix(target.before.text_matrix))
    target.before.font_size.abs() *
    (basis.c * basis.c + basis.d * basis.d).sqrt()
  } else if target.kind == "text-form" {
    number(get(session.document, target.reference, "ODSize")) *
    (target.matrix.c * target.matrix.c + target.matrix.d * target.matrix.d).sqrt()
  } else {
    0.0
  }
  guard !size.is_nan() && !size.is_inf() && size >= 0 && size <= 14400 else {
    @failure.reject(
      "protected-content", "Source font size cannot be edited within the geometry budget",
    )
  }
  size
}

///|
fn source_reason(
  session : PdfSession,
  display : PageDisplay,
  target : PdfSourceObject,
) -> String {
  if !session.readOnlyReason.is_empty() {
    return session.readOnlyReason
  }
  if !display.displayComplete {
    return "Page drawing is incomplete; source editing is protected"
  }
  if !target.reason.is_empty() {
    return target.reason
  }
  if target.location is None {
    return "PDF operator cannot be isolated to one source stream"
  }
  if target.spans.any(span => !span.mapped || span.invisible) {
    return "PDF source text is unknown or invisible"
  }
  try {
    let catalog = resolve(
      session.document,
      @syntax.PdfIndirect(session.document.root()),
    )
    if raw(catalog, "StructTreeRoot") != @syntax.PdfNull {
      return "Tagged PDF source editing requires synchronized structure"
    }
    if source_text(display, target).length() > 32767 {
      return "PDF source object exceeds the editable text budget"
    }
    ignore(source_placement(session, target))
    ignore(source_font_size(session, target))
    if target.kind == "text" {
      ignore(source_restore_ops(target.after))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn source_object_json(
  session : PdfSession,
  display : PageDisplay,
  target : PdfSourceObject,
) -> Json raise @failure.Failure {
  let reason = source_reason(session, display, target)
  let placement = source_placement(session, target) catch {
    _ => { x: 0, y: 0, width: 1, height: 1, rotation: 0, }
  }
  let size = source_font_size(session, target) catch { _ => 0.0 }
  let role = if target.kind == "text-form" {
    get(session.document, target.reference, "ODRole")
  } else {
    @syntax.PdfNull
  }
  {
    "id": target.id,
    "kind": if target.kind.has_prefix("text") {
      "text"
    } else {
      "image"
    },
    "placement": placement,
    "text": source_text(display, target),
    "font": target.font,
    "color": target.color,
    "size": size,
    "foreground": true,
    "role": if role is PdfNameObject(name) {
      @utf8.decode_lossy(name.bytes())[1:].to_owned()
    } else {
      "text"
    },
    "readOnlyReason": reason,
  }
}
