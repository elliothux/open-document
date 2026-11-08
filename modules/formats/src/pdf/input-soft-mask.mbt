///|
fn read_soft_mask(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  resources : @syntax.PdfObject,
  state : GraphicsState,
) -> SoftMask? raise @failure.Failure {
  if is_name(object, "None") {
    return None
  }
  let kind = get(document, object, "Type")
  guard kind == @syntax.PdfNull || is_name(kind, "Mask") else {
    @failure.reject("invalid-pdf", "Invalid PDF soft mask type")
  }
  guard object is PdfDictionary(entries) &&
    entries.all(entry => {
      ["/Type", "/S", "/G", "/TR", "/BC"].contains(
        @utf8.decode_lossy(entry.0.bytes()),
      )
    }) &&
    is_name(get(document, object, "S"), "Alpha") else {
    @failure.reject("unsupported-pdf", "Unsupported PDF soft mask")
  }
  let transfer = get(document, object, "TR")
  guard transfer == @syntax.PdfNull ||
    is_name(transfer, "Identity") ||
    is_name(transfer, "Default") else {
    @failure.reject(
      "unsupported-pdf", "PDF soft mask transfer functions are unsupported",
    )
  }
  let backdrop = get(document, object, "BC")
  if backdrop != @syntax.PdfNull {
    guard backdrop is PdfArray(values) &&
      values.length() >= 1 &&
      values.length() <= 4 else {
      @failure.reject("invalid-pdf", "Invalid PDF mask backdrop")
    }
    for value in values {
      ignore(number(resolve(document, value)))
    }
  }
  let group = raw(object, "G")
  guard group is PdfIndirect(_) &&
    resolve(document, group) is PdfStreamObject(_) else {
    @failure.reject("invalid-pdf", "PDF soft mask requires a Form stream")
  }
  Some({ group, resources, state: { ..state, softMask: None, }, })
}

///|
fn ContentContext::soft_mask_commands(
  self : ContentContext,
  mask : SoftMask,
  depth : Int32,
) -> Array[@layout.DrawCommand] raise {
  let document = self.session.document
  guard mask.group is PdfIndirect(id) else {
    abort("Soft mask stream is indirect")
  }
  let key = "pdf-image-\{id}"
  guard !self.forms.contains(key) else {
    @failure.reject("invalid-pdf", "Cyclic PDF soft mask")
  }
  self.forms[key] = true
  defer self.forms.remove(key)
  let object = resolve(document, mask.group)
  guard is_name(get(document, object, "Subtype"), "Form") &&
    [@syntax.PdfNull, @syntax.PdfInteger(1)].contains(
      get(document, object, "FormType"),
    ) else {
    @failure.reject("invalid-pdf", "Invalid PDF soft mask Form")
  }
  let own = get(document, object, "Resources")
  let resources = if own == @syntax.PdfNull { mask.resources } else { own }
  guard transparency_group(self, object, resources, alpha=true) is Some(_) else {
    @failure.reject(
      "invalid-pdf", "PDF soft mask requires a transparency group",
    )
  }
  let state = {
    ..mask.state,
    matrix: mask.state.matrix.then(
      pdf_object_matrix(get(document, object, "Matrix")),
    ),
    style: { ..mask.state.style, fillAlpha: 1, strokeAlpha: 1, blend: Normal, },
    clips: 0,
  }
  let child : ContentContext = {
    ..self,
    extraction: None,
    sources: [],
    collectSource: false,
    commands: [],
    diagnostics: [],
    spans: [],
    chunks: [],
    units: 0,
    textComplete: true,
    displayComplete: true,
    marked: [],
    nesting: 0,
  }
  let (x, y, r, t) = rectangle(get(document, object, "BBox"))
  child.scope(
    @layout.ClipPath(
      path_in(
        [
          @layout.Move(x, y),
          @layout.Line(r, y),
          @layout.Line(r, t),
          @layout.Line(x, t),
          @layout.Close,
        ],
        state.matrix,
      ),
      false,
    ),
  )
  interpret(
    child,
    stream_bytes(document, mask.group),
    resources,
    "soft-mask:\{id}",
    state,
    depth + 1,
  )
  child.restore()
  guard child.displayComplete else {
    @failure.reject("unsupported-pdf", "PDF soft mask content is incomplete")
  }
  self.diagnostics.append(child.diagnostics)
  child.commands
}

///|
fn ContentContext::apply_mask(
  self : ContentContext,
  state : GraphicsState,
  start : Int32,
  depth : Int32,
) -> Unit raise {
  guard state.softMask is Some(mask) && self.commands.length() > start else {
    return
  }
  let mask = self.soft_mask_commands(mask, depth)
  let commands = self.commands[start:].to_owned()
  input_layer_budget(mask, 2)
  input_layer_budget(commands, 2)
  self.commands.truncate(start)
  self.commands.push(@layout.Style(state.style))
  self.commands.push(@layout.Mask(mask, commands))
}
