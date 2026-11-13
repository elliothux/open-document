///|
fn transparency_group(
  context : ContentContext,
  object : @syntax.PdfObject,
  resources : @syntax.PdfObject,
  alpha~ : Bool = false,
) -> Bool? raise {
  let document = context.session.document
  let group = get(document, object, "Group")
  if group == @syntax.PdfNull {
    return None
  }
  guard group is PdfDictionary(entries) &&
    entries.all(entry => {
      ["/Type", "/S", "/CS", "/I", "/K"].contains(
        @utf8.decode_lossy(entry.0.bytes()),
      )
    }) &&
    is_name(get(document, group, "S"), "Transparency") else {
    @failure.reject("invalid-pdf", "Invalid PDF page transparency group")
  }
  let kind = get(document, group, "Type")
  guard kind == @syntax.PdfNull || is_name(kind, "Group") else {
    @failure.reject("invalid-pdf", "Invalid PDF transparency group type")
  }
  let isolated = get(document, group, "I")
  guard isolated == @syntax.PdfNull || isolated is PdfBoolean(_) else {
    @failure.reject("invalid-pdf", "Invalid PDF group isolation")
  }
  let knockout = get(document, group, "K")
  guard knockout == @syntax.PdfNull || knockout == @syntax.PdfBoolean(false) else {
    @failure.reject("unsupported-pdf", "PDF knockout groups are unsupported")
  }
  let source = get(document, group, "CS")
  if source != @syntax.PdfNull {
    let space = context.color_space(resources, source)
    // Native RGB output blends converted colors; the profile remains authoritative for source colors.
    let rgb = space.srgb_blending() ||
      (space is IccColor(profile) && profile.curves.length() == 3)
    guard !(space is PatternColor(_)) && (alpha || rgb) else {
      @failure.reject(
        "unsupported-pdf", "Unsupported PDF group blending color space",
      )
    }
  }
  guard alpha ||
    context.color_space(resources, tag("DeviceRGB")).srgb_blending() else {
    @failure.reject(
      "unsupported-pdf", "Unsupported PDF group blending color space",
    )
  }
  Some(isolated == @syntax.PdfBoolean(true))
}

///|
fn page_transparency_group(
  context : ContentContext,
  object : @syntax.PdfObject,
  resources : @syntax.PdfObject,
) -> Bool raise {
  // A page group is isolated regardless of its I entry; annotations paint afterward.
  transparency_group(context, object, resources) is Some(_)
}

///|
fn input_layer_budget(
  commands : Array[@layout.DrawCommand],
  depth : Int32,
  normal~ : Bool = false,
) -> Unit raise {
  guard depth <= @layout.DrawingLayerCount else {
    @failure.reject("limit-exceeded", "PDF drawing layers exceed budget")
  }
  for command in commands {
    @pdfcore.sdk_check(1)
    match command {
      Style(style) if normal && style.blend != Normal =>
        @failure.reject(
          "unsupported-pdf", "Nonisolated PDF groups with outer compositing require Normal inner blending",
        )
      Layer(_, children) => input_layer_budget(children, depth + 1, normal~)
      Tile(_, _, _, _, _, _, _, children) =>
        input_layer_budget(children, depth + 1, normal~)
      Mask(mask, children, ..) => {
        input_layer_budget(mask, depth + 2, normal~)
        input_layer_budget(children, depth + 1, normal~)
      }
      _ => ()
    }
  }
}

///|
fn ContentContext::isolate_form(
  self : ContentContext,
  start : Int32,
  state : GraphicsState,
  normal~ : Bool = false,
  box~ : @layout.Border,
  matrix~ : @layout.Matrix,
) -> Unit raise {
  let commands = self.commands[start:].to_owned()
  let commands = if form_clip_redundant(commands, box, matrix) {
    commands[1:commands.length() - 1].to_owned()
  } else {
    commands
  }
  input_layer_budget(commands, 1, normal~)
  self.commands.truncate(start)
  self.commands.push(@layout.Style(state.style))
  self.commands.push(@layout.Layer(state.style.fillAlpha, commands))
}
