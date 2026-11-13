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
  let width = if stroke { state.width } else { 0.0 }
  check_style(state.style, width, matrix=state.matrix)
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
    let command = @layout.DrawCommand::linear_path(
      path_in(path, state.matrix.inverse()),
      fill,
      stroke,
      width,
      style,
      8192 - self.preparedStrokePoints.val,
    )
    if command is OutlinedPath(_, _, _, _, outline) {
      self.preparedStrokePoints.val += outline.length()
    } else if command is DashedPath(_, _, _, _, pieces) {
      self.preparedStrokePoints.val += pieces.fold(init=0, (sum, piece) => {
        sum + piece.length()
      })
    } else if command is RectangleDashedPath(_, _, _, _, spans) {
      self.preparedStrokePoints.val += spans.length() * 2
    }
    self.commands.push(command.prepare_fill_outline(style))
    self.restore()
    self.apply_mask(state, command_start, depth)
  }
}
