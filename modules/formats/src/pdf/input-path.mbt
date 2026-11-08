///|
fn ContentContext::paint_path(
  self : ContentContext,
  path : Array[@layout.PathSegment],
  state : GraphicsState,
  op : @content.PdfContentOp,
  base : @layout.Matrix,
  depth : Int32,
) -> Unit raise {
  let fill = !(op is (Op_S | Op_s))
  let stroke = !(op is (Op_f | Op_F | Op_fstar))
  check_style(state.style, state.width)
  let even_odd = op is (Op_fstar | Op_Bstar | Op_bstar)
  // Fill/stroke are separate painting steps when either requires a pattern or soft mask.
  let paints = if fill &&
    stroke &&
    (
      state.softMask is Some(_) ||
      state.fillSpace is PatternColor(_) ||
      state.strokeSpace is PatternColor(_)
    ) {
    [(true, false), (false, true)]
  } else {
    [(fill, stroke)]
  }
  for (fill, stroke) in paints {
    if fill && state.fillSpace is PatternColor(_) {
      self.tiling_pattern(path, state, base, even_odd, depth)
      continue
    }
    guard !stroke || !(state.strokeSpace is PatternColor(_)) else {
      @failure.reject(
        "unsupported-pdf", "Pattern strokes require a stroke outline",
      )
    }
    let fill = if fill { state.fill } else { "" }
    let stroke = if stroke { state.stroke } else { "" }
    let command_start = self.commands.length()
    let style = { ..state.style, evenOdd: even_odd, }
    self.commands.push(@layout.Style(style))
    self.scope(@layout.Transform(state.matrix))
    self.extracted_path(path, state, fill, stroke, style, depth)
    self.commands.push(
      @layout.Path(
        path_in(path, state.matrix.inverse()),
        fill,
        stroke,
        state.width,
      ),
    )
    self.restore()
    self.apply_mask(state, command_start, depth)
  }
}
