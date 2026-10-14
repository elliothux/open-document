///|
fn show_text(
  context : ContentContext,
  state : GraphicsState,
  op : @content.PdfContentOp,
  source : String,
) -> GraphicsState raise {
  guard state.font is Some(font) else {
    @failure.reject("unsupported-pdf", "PDF text has no font resource")
  }
  if font.cid {
    let strings = match op {
      Op_Tj(bytes) | Op_quote(bytes) | Op_double_quote(_, _, bytes) => [bytes]
      Op_TJ(PdfArray(items)) =>
        items.filter_map(item => {
          match item {
            PdfString(bytes) => Some(bytes)
            _ => None
          }
        })
      _ => []
    }
    guard strings.all(bytes => bytes.length() % 2 == 0) else {
      @failure.reject(
        "invalid-pdf", "Identity-H text requires complete two-byte codes",
      )
    }
  }
  let text_state = state.text.content_apply_text_state_op(op)
  guard text_state.font_size.abs() <= 14400 &&
    [0, 3].contains(text_state.rendering_mode) else {
    @failure.reject(
      "unsupported-pdf", "PDF text stroke, clipping, or size is unsupported",
    )
  }
  let result = state.text.content_apply_text_op(
    font.font,
    geometry_matrix(state.matrix),
    op,
  )
  for index, glyph in result.glyphs {
    @pdfcore.sdk_check(1)
    let box = glyph.bounding_box
    let quad = [box.x0, box.y0, box.x1, box.y1, box.x2, box.y2, box.x3, box.y3]
    let metrics = font.font.content_extra_metrics()
    let quad = if metrics.0 < metrics.1 {
      [quad[2], quad[3], quad[0], quad[1], quad[6], quad[7], quad[4], quad[5]]
    } else {
      quad
    }
    guard quad.all(value => {
      !value.is_nan() && !value.is_inf() && value.abs() <= 1000000000
    }) else {
      @failure.reject("limit-exceeded", "PDF text geometry exceeds budget")
    }
    let mapped = font.unicode(glyph.charcode)
    let actual = context.marked.any(mark => mark.replacement is Some(_))
    let value = mapped.unwrap_or("\u{fffc}")
    if !actual && mapped is None {
      context.textComplete = false
    }
    if !actual {
      separate_text(context, quad, value)
    }
    let start = context.units
    if !actual {
      context.append(value)
    }
    context.spans.push({
      start,
      end: context.units,
      text: if actual {
        ""
      } else {
        value
      },
      quad,
      source: "\{source}:\{index}",
      mapped: mapped is Some(_) || actual,
      invisible: text_state.rendering_mode == 3,
    })
    if text_state.rendering_mode == 3 || text_state.font_size == 0 {
      continue
    }
    if font.index is Some(font_index) {
      let id = if font.cid && !font.substituted {
        match font.gidMap {
          None => glyph.charcode
          Some(bytes) =>
            if glyph.charcode >= 0 && glyph.charcode < bytes.length() / 2 {
              bytes[glyph.charcode * 2].to_int() * 256 +
              bytes[glyph.charcode * 2 + 1].to_int()
            } else {
              0
            }
        }
      } else {
        -1
      }
      let encoded = if font.substituted {
        mapped
      } else {
        source_unicode(encoded_font(font.font), glyph.charcode)
      }
      let point = encoded
        .filter(text => text.iter().count() == 1)
        .map(text => text.iter().next().unwrap().to_int())
        .unwrap_or(
          if font.symbolic && !font.substituted {
            glyph.charcode
          } else {
            -1
          },
        )
      let outline = match font.glyphs.get(glyph.charcode) {
        Some(Some(outline)) => outline
        Some(None) => {
          context.displayComplete = false
          continue
        }
        None => {
          let outline = context.probe.source_glyph(
            font_index,
            id,
            if font.cid {
              ""
            } else {
              font.font.sdk_glyph_name(glyph.charcode)
            },
            point,
            font.symbolic && !font.substituted,
          ) catch {
            @failure.Failure(
              code="missing-glyph"
              | "unsupported-font",
              message~,
              ..
            ) => {
              context.displayComplete = false
              font.glyphs[glyph.charcode] = None
              context.diagnostics.push(message)
              continue
            }
            error => raise error
          }
          font.glyphs[glyph.charcode] = Some(outline)
          outline
        }
      }
      let transform = state.matrix
        .then(matrix(glyph.text_matrix))
        .then({
          a: text_state.font_size * text_state.horizontal_scaling,
          b: 0,
          c: 0,
          d: text_state.font_size,
          e: 0,
          f: text_state.rise,
        })
      check_style(state.style, state.width)
      context.commands.push(@layout.Style(state.style))
      context.scope(@layout.Transform(transform))
      context.commands.push(
        @layout.Glyphs(0, 0, state.fill, [
          {
            outline: outline.0,
            x: glyph.pvx,
            y: -glyph.pvy,
            scaleX: 1.0 / outline.1.to_double(),
            scaleY: 1.0 / outline.1.to_double(),
          },
        ]),
      )
      context.restore()
    } else {
      context.displayComplete = false
    }
  }
  { ..state, text: result.text_state, }
}

///|
fn finish_marked(context : ContentContext) -> Unit raise @failure.Failure {
  guard context.marked.pop() is Some(mark) else {
    @failure.reject("invalid-pdf", "PDF marked content stack underflow")
  }
  if mark.replacement is Some(replacement) &&
    !context.marked.any(parent => parent.replacement is Some(_)) {
    let spans = context.spans[mark.span:].to_owned()
    while context.spans.length() > mark.span {
      ignore(context.spans.pop())
    }
    while context.chunks.length() > mark.chunk {
      ignore(context.chunks.pop())
    }
    context.units = mark.offset
    if !spans.is_empty() {
      separate_text(context, spans[0].quad, replacement)
    }
    let offset = context.units
    context.append(replacement)
    for index, span in spans {
      context.spans.push({
        ..span,
        start: offset,
        end: context.units,
        text: if index == 0 {
          replacement
        } else {
          ""
        },
        mapped: true,
        source: "ActualText:" + span.source,
      })
    }
  }
}

///|
fn separate_text(
  context : ContentContext,
  quad : Array[Double],
  value : String,
) -> Unit raise @failure.Failure {
  if context.spans.is_empty() {
    return
  }
  let previous = context.spans[context.spans.length() - 1]
  let q = previous.quad
  let dx = q[6] - q[0]
  let dy = q[7] - q[1]
  let length = (dx * dx + dy * dy).sqrt()
  let last = context.chunks.last().unwrap_or("")
  if length > 0 &&
    !last.has_suffix(" ") &&
    !last.has_suffix("\n") &&
    !value.has_prefix(" ") {
    let px = quad[0] - q[6]
    let py = quad[1] - q[7]
    let height = ((q[2] - q[0]) * (q[2] - q[0]) + (q[3] - q[1]) * (q[3] - q[1])).sqrt()
    let across = (px * dx + py * dy) / length
    let vertical = (px * dy - py * dx).abs() / length
    if vertical > height.max(1) * 0.5 {
      context.append("\n")
    } else if across > height.max(1) * 0.15 {
      context.append(" ")
    }
  }
}
