///|
fn text_stroked(mode : Int32) -> Bool {
  mode == 1 || mode == 2
}

///|
fn draw_stroked_glyph(
  context : ContentContext,
  path : Array[@layout.PathSegment],
  placement : @layout.Matrix,
  state : GraphicsState,
) -> Unit raise {
  guard !path.is_empty() else { return }
  guard !(state.strokeSpace is PatternColor(_)) else {
    @failure.reject(
      "unsupported-pdf", "Pattern text stroke requires a stroke outline",
    )
  }
  @pdfcore.sdk_check(path.length())
  @pdfcore.sdk_decoded(path.length() * 56)
  check_style(state.style, state.width, matrix=state.matrix)
  let path = path_in(path, placement)
  let fill = if state.text.rendering_mode == 2 { state.fill } else { "" }
  context.commands.push(@layout.Style({ ..state.style, evenOdd: false, }))
  // Transform the glyph into user space before applying the PDF line width.
  context.scope(@layout.Transform(state.matrix))
  context.commands.push(@layout.Path(path, fill, state.stroke, state.width))
  context.restore()
}
