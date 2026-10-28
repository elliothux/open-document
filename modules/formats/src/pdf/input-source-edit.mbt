///|
fn source_restore_ops(
  state : @pdflite.PdfContentTextState,
) -> Array[@content.PdfContentOp] raise @failure.Failure {
  guard state.font_size > 0 &&
    state.horizontal_scaling > 0 &&
    !state.font.is_empty() else {
    @failure.reject(
      "protected-content", "PDF text state cannot be restored safely",
    )
  }
  let relative = matrix(state.line_matrix)
    .inverse()
    .then(matrix(state.text_matrix))
  guard (relative.a - 1).abs() < 0.000001 &&
    relative.b.abs() < 0.000001 &&
    relative.c.abs() < 0.000001 &&
    (relative.d - 1).abs() < 0.000001 &&
    relative.f.abs() < 0.000001 else {
    @failure.reject(
      "protected-content", "Non-horizontal PDF text advance is protected",
    )
  }
  let advance = -relative.e *
    1000 /
    (state.font_size * state.horizontal_scaling)
  guard !advance.is_nan() && !advance.is_inf() && advance.abs() <= 1000000000 else {
    @failure.reject("limit-exceeded", "PDF text advance exceeds budget")
  }
  [
    @content.Op_Tf(name(state.font), state.font_size),
    @content.Op_Tc(state.character_spacing),
    @content.Op_Tw(state.word_spacing),
    @content.Op_Tz(state.horizontal_scaling * 100),
    @content.Op_TL(state.leading),
    @content.Op_Tr(state.rendering_mode),
    @content.Op_Ts(state.rise),
    @content.Op_Tm(state.line_matrix),
    @content.Op_TJ(@syntax.PdfArray([@syntax.PdfReal(advance)])),
  ]
}

///|
fn source_placement_matrix(
  placement : PdfPlacement,
) -> @layout.Matrix raise @failure.Failure {
  check_pdf_placement(placement)
  let angle = placement.rotation * 3.141592653589793 / 180
  {
    a: @math.cos(angle),
    b: @math.sin(angle),
    c: -@math.sin(angle),
    d: @math.cos(angle),
    e: placement.x,
    f: placement.y,
  }
}

///|
fn patch_pdf_bytes(
  bytes : Bytes,
  start : Int32,
  end : Int32,
  replacement : Bytes,
) -> Bytes raise @failure.Failure {
  guard start >= 0 &&
    end >= start &&
    end <= bytes.length() &&
    replacement.length().to_int64() +
    bytes.length().to_int64() -
    (end - start).to_int64() <=
    16777216 else {
    @failure.reject("limit-exceeded", "PDF source patch exceeds stream bounds")
  }
  Bytes::makei(start + replacement.length() + bytes.length() - end, i => {
    if i < start {
      bytes[i]
    } else if i - start < replacement.length() {
      replacement[i - start]
    } else {
      bytes[end + i - start - replacement.length()]
    }
  })
}

///|
fn PdfTransaction::copy_source_stream(
  self : PdfTransaction,
  number : Int32,
  bytes : Bytes,
  resources : @syntax.PdfObject,
  form : Bool,
) -> @syntax.PdfObject raise {
  guard self.session.document.lookup_object_or_null(number)
    is PdfStreamObject(original) else {
    @failure.reject(
      "protected-content", "PDF target must have an indirect source stream",
    )
  }
  let mut dictionary = original.dictionary
    .deep_copy()
    .remove_dict_entry(pdf_name("Filter"))
    .remove_dict_entry(pdf_name("DecodeParms"))
    .with_entry(pdf_name("Length"), @syntax.PdfInteger(bytes.length()))
  if form {
    dictionary = dictionary.with_entry(pdf_name("Resources"), resources)
  }
  self.add(@syntax.pdf_stream(dictionary, @syntax.StreamGot(bytes)))
}

///|
fn with_pdf_xobject(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  key : String,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise @failure.Failure {
  let resources = resolve(document, resources).deep_copy()
  let objects = get(document, resources, "XObject")
  let objects = if objects == @syntax.PdfNull {
    dict([])
  } else {
    objects.deep_copy()
  }
  resources.with_entry(
    pdf_name("XObject"),
    objects.with_entry(pdf_name(key), object),
  )
}

///|
fn PdfTransaction::rewrite_source(
  self : PdfTransaction,
  page : SourcePage,
  target : PdfSourceObject,
  bytes : Bytes,
  resources : @syntax.PdfObject,
) -> Unit raise {
  guard target.location is Some(location) else {
    @failure.reject("protected-content", "PDF target cannot be isolated")
  }
  let original = stream_bytes(
    self.session.document,
    @syntax.PdfIndirect(location.number),
  )
  let patched = patch_pdf_bytes(original, location.start, location.end, bytes)
  let mut resources = resources
  let mut reference = self.copy_source_stream(
    location.number,
    patched,
    resources,
    !location.path.is_empty(),
  )
  for i = location.path.length() - 1; i >= 0; i = i - 1 {
    let call = location.path[i]
    let key = "ODSource\{self.next}"
    resources = with_pdf_xobject(
      self.session.document,
      call.resources,
      key,
      reference,
    )
    let original = stream_bytes(
      self.session.document,
      @syntax.PdfIndirect(call.number),
    )
    let bytes = @pdflite.pdf_content_bytes_of_ops([@content.Op_Do(name(key))])
    reference = self.copy_source_stream(
      call.number,
      patch_pdf_bytes(original, call.start, call.end, bytes),
      resources,
      i > 0,
    )
  }
  let contents = page_contents(self.session.document, self.object(page.number))
  guard location.rootIndex < contents.length() else {
    @failure.reject("protected-content", "PDF source stream index is stale")
  }
  contents[location.rootIndex] = reference
  self.objects[page.number] = self
    .object(page.number)
    .with_entry(pdf_name("Contents"), @syntax.PdfArray(contents))
    .with_entry(pdf_name("Resources"), resources)
}

///|
fn source_check_clips(
  session : PdfSession,
  target : PdfSourceObject,
  placement : PdfPlacement,
) -> Unit raise @failure.Failure {
  guard target.location is Some(location) else {
    @failure.reject("protected-content", "PDF source path is unavailable")
  }
  let screen = source_placement_matrix(placement)
  for call in location.path {
    let inverse = call.clip.inverse()
    let (x, y, r, t) = rectangle(
      get(session.document, @syntax.PdfIndirect(call.child), "BBox"),
    )
    for
      (u, v) in [
        (0.0, 0.0),
        (placement.width, 0),
        (placement.width, placement.height),
        (0, placement.height),
      ] {
      let (sx, sy) = screen.point(u, v)
      let (px, py) = inverse.point(sx, sy)
      guard px >= x - 0.000001 &&
        py >= y - 0.000001 &&
        px <= r + 0.000001 &&
        py <= t + 0.000001 else {
        @failure.reject(
          "protected-content", "PDF edit would leave the containing Form clip",
        )
      }
    }
  }
}

///|
fn source_logical_box(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (Double, Double, Double, Double) raise @failure.Failure {
  let logical = get(document, object, "ODLogicalBox")
  rectangle(
    if logical == @syntax.PdfNull {
      get(document, object, "BBox")
    } else {
      logical
    },
  )
}

///|
fn PdfTransaction::source_form_ops(
  self : PdfTransaction,
  target : PdfSourceObject,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
) -> (Array[@content.PdfContentOp], @syntax.PdfObject) raise {
  source_check_clips(self.session, target, placement)
  guard target.location is Some(location) else {
    @failure.reject("protected-content", "PDF source location is unavailable")
  }
  let object = if form is PdfIndirect(number) {
    self.object(number)
  } else {
    form
  }
  let (x, y, r, t) = source_logical_box(self.session.document, object)
  let width = r - x
  let height = t - y
  let desired = source_placement_matrix(placement).then({
    a: placement.width / width,
    b: 0,
    c: 0,
    d: -placement.height / height,
    e: -x * placement.width / width,
    f: placement.height + y * placement.height / height,
  })
  let parent = if target.kind.has_suffix("-form") {
    target.matrix.then(
      pdf_object_matrix(get(self.session.document, target.reference, "Matrix")).inverse(),
    )
  } else {
    target.matrix
  }
  let own = pdf_object_matrix(get(self.session.document, object, "Matrix"))
  let transform = parent.inverse().then(desired).then(own.inverse())
  ignore(transform.inverse())
  let key = "ODSource\{self.next}"
  let resources = with_pdf_xobject(
    self.session.document,
    location.resources,
    key,
    form,
  )
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_cm(geometry_matrix(transform)),
    @content.Op_Do(name(key)),
    @content.Op_Q,
  ]
  (ops, resources)
}

///|
fn PdfSession::source_target(
  self : PdfSession,
  display : PageDisplay,
  id : String,
) -> PdfSourceObject raise @failure.Failure {
  self.check(display.revision)
  let targets = display.sources.filter(target => target.id == id)
  guard targets.length() == 1 else {
    @failure.reject("stale-object", "PDF source object identity is stale")
  }
  targets[0]
}

///|
fn source_checked_target(
  session : PdfSession,
  display : PageDisplay,
  id : String,
) -> PdfSourceObject raise @failure.Failure {
  let target = session.source_target(display, id)
  let reason = source_reason(session, display, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if target.kind == "text" {
    ignore(source_restore_ops(target.after))
  }
  target
}

///|
fn PdfTransaction::write_source_object(
  self : PdfTransaction,
  page : SourcePage,
  target : PdfSourceObject,
  ops : Array[@content.PdfContentOp],
  resources : @syntax.PdfObject,
) -> Unit raise {
  let output : Array[@content.PdfContentOp] = []
  if target.kind == "text" {
    guard (match target.op {
      Op_Tj(_) | Op_TJ(_) | Op_quote(_) | Op_double_quote(_, _, _) => true
      _ => false
    }) else {
      @failure.reject(
        "protected-content", "PDF text source operator is unsupported",
      )
    }
    output.push(@content.Op_ET)
  }
  output.append(ops)
  if target.kind == "text" {
    output.push(@content.Op_BT)
    output.append(source_restore_ops(target.after))
  }
  self.rewrite_source(
    page,
    target,
    @pdflite.pdf_content_bytes_of_ops(output),
    resources,
  )
}

///|
fn source_edit_probe(
  supplied : @layout.TextProbe,
  source : @layout.TextProbe,
) -> @layout.TextProbe raise @failure.Failure {
  let combined = @layout.TextProbe::new()
  errdefer combined.close()
  for probe in [supplied, source] {
    for index, info in probe.font_info() {
      if !combined
        .font_info()
        .any(existing => existing.identity == info.identity) {
        ignore(combined.add_font(probe.font_bytes(index), info.identity))
      }
    }
  }
  combined
}

///|
pub fn PdfSession::replace_source_text(
  self : PdfSession,
  revision : Int32,
  page : String,
  id : String,
  spec : PdfTextSpec,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(page)
  pdf_bound(self.budget, () => {
    let display = self.build_display(
      page.id,
      supplied,
      profile,
      @layout.Images::new(),
    )
    defer display.probe.close()
    let target = source_checked_target(self, display, id)
    guard target.kind.has_prefix("text") else {
      @failure.reject("invalid-operation", "Choose a PDF text object")
    }
    let combined = source_edit_probe(supplied, display.probe)
    defer combined.close()
    let profile = profile.copy()
    if combined.font_info().any(info => info.identity == spec.font) {
      profile[spec.font] = spec.font
    }
    if spec.font == target.font &&
      !profile.contains(spec.font) &&
      target.fontIndex is Some(index) {
      let identity = display.probe.font_info()[index].identity
      profile[spec.font] = identity
    }
    let form = tx.text_form(spec, combined, profile)
    let (ops, resources) = tx.source_form_ops(target, form, spec.placement)
    tx.write_source_object(page, target, ops, resources)
    tx.commit(self.current)
  })
}

///|
fn PdfTransaction::original_source_form(
  self : PdfTransaction,
  display : PageDisplay,
  target : PdfSourceObject,
) -> @syntax.PdfObject raise {
  if target.kind.has_suffix("-form") {
    return target.reference
  }
  let placement = source_placement(self.session, target)
  let resources = target.location.unwrap().resources
  if target.kind == "image" {
    let object = appearance_stream(
      @pdflite.pdf_content_bytes_of_ops([
        @content.Op_q,
        @content.Op_cm({
          a: placement.width,
          b: 0,
          c: 0,
          d: placement.height,
          e: 0,
          f: 0,
        }),
        @content.Op_Do(name("Image")),
        @content.Op_Q,
      ]),
      placement.width,
      placement.height,
      dict([("XObject", dict([("Image", target.reference)]))]),
    )
    guard object is PdfStreamObject(s) else {
      abort("Expected source image Form")
    }
    return self.add(
      @syntax.pdf_stream(
        s.dictionary.with_entry(name("ODKind"), tag("Image")),
        s.data,
      ),
    )
  }
  let flip : @layout.Matrix = {
    a: 1,
    b: 0,
    c: 0,
    d: -1,
    e: 0,
    f: placement.height,
  }
  let transform = source_placement_matrix(placement)
    .then(flip)
    .inverse()
    .then(target.matrix)
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_cm(geometry_matrix(transform)),
    @content.Op_rg(
      channel(target.color, 0),
      channel(target.color, 2),
      channel(target.color, 4),
    ),
    @content.Op_BT,
  ]
  ops.append(source_restore_ops(target.before))
  ops.push(target.op)
  ops.push(@content.Op_ET)
  ops.push(@content.Op_Q)
  let padding = target.before.font_size.abs() * 2
  let form = stream(@pdflite.pdf_content_bytes_of_ops(ops), [
    ("Type", tag("XObject")),
    ("Subtype", tag("Form")),
    (
      "BBox",
      pdf_rectangle(
        -padding,
        -padding,
        placement.width + padding,
        placement.height + padding,
      ),
    ),
    ("ODLogicalBox", pdf_rectangle(0, 0, placement.width, placement.height)),
    ("Resources", resources),
    ("ODKind", tag("Text")),
    ("ODText", pdf_string(source_text(display, target))),
    ("ODFont", pdf_string(target.font)),
    ("ODColor", pdf_string(target.color)),
    ("ODSize", @syntax.PdfReal(target.before.font_size)),
    ("ODRole", tag("text")),
  ])
  self.add(form)
}

///|
pub fn PdfSession::change_source_object(
  self : PdfSession,
  revision : Int32,
  page : String,
  id : String,
  placement : PdfPlacement?,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(page)
  pdf_bound(self.budget, () => {
    let display = self.build_display(
      page.id,
      supplied,
      profile,
      @layout.Images::new(),
    )
    defer display.probe.close()
    let target = source_checked_target(self, display, id)
    let (ops, resources) = if placement is Some(placement) {
      let form = tx.original_source_form(display, target)
      tx.source_form_ops(target, form, placement)
    } else {
      ([], target.location.unwrap().resources)
    }
    tx.write_source_object(page, target, ops, resources)
    tx.commit(self.current)
  })
}

///|
fn PdfTransaction::replace_source_image(
  self : PdfTransaction,
  page : SourcePage,
  id : String,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise {
  let display = self.session.build_display(
    page.id,
    supplied,
    profile,
    @layout.Images::new(),
  )
  defer display.probe.close()
  let target = source_checked_target(self.session, display, id)
  guard target.kind.has_prefix("image") else {
    @failure.reject("invalid-operation", "Choose a PDF image object")
  }
  let (ops, resources) = self.source_form_ops(target, form, placement)
  self.write_source_object(page, target, ops, resources)
}
