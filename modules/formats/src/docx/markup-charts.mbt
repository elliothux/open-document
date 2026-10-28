///|
fn Session::markup_charts(
  self : Session,
  tree : WordTree,
  flow : @layout.Flow,
  layout : @layout.Layout?,
) -> (Map[Int32, @layout.PlacedDrawingFrame], Map[String, String]) raise @failure.Failure {
  let expected : Map[Int32, @layout.DrawingFrame] = Map([])
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if span.drawing is Some(frame) && frame.content is Chart(_) {
        expected[span.node] = frame
      }
    }
  }
  if expected.is_empty() {
    return (Map([]), Map([]))
  }
  guard layout is Some(layout) && layout.revision == self.revision else {
    @failure.reject("stale-layout", "Chart markup requires the current layout")
  }
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Chart markup requires a complete layout",
    )
  }
  let keys : Map[(Int32, Int32), Int32] = Map([])
  let offsets : Map[Int32, Int32] = Map([])
  for item in docx_texts(tree) {
    let offset = offsets.get(item.paragraph).unwrap_or(0)
    if expected.contains(item.id) {
      keys[(item.paragraph, offset)] = item.id
    }
    offsets[item.paragraph] = offset + inline_text(tree.nodes[item.id]).length()
  }
  let charts : Map[Int32, @layout.PlacedDrawingFrame] = Map([])
  for page in layout.pages {
    for line in page.lines {
      for frame in line.drawings {
        if keys.get((line.paragraph, frame.start)) is Some(id) &&
          frame.content is Chart(chart) {
          let source = expected[id]
          guard source.content is Chart(original) &&
            chart.data == original.data &&
            frame.width == source.width &&
            frame.height == source.height &&
            !chart.primitives.is_empty() else {
            @failure.reject(
              "stale-layout", "Chart layout does not match native content",
            )
          }
          charts[id] = frame
        }
      }
    }
  }
  guard charts.length() == expected.length() else {
    @failure.reject("unsupported-layout", "Chart position is unavailable")
  }
  (
    charts,
    Map::from_array(layout.outlines.map(outline => (outline.key, outline.path))),
  )
}

///|
fn chart_markup_svg(
  frame : @layout.PlacedDrawingFrame,
  output : MarkupOutput,
) -> String raise @failure.Failure {
  guard frame.content is Chart(chart) else {
    @failure.reject("unsupported-output", "Chart markup requires a chart")
  }
  let id = output.chart_index
  output.chart_index += 1
  let inner = {
    ..output,
    builder: StringBuilder(),
    units: 0,
    limit: output.limit - output.units,
  }
  let label = property_attribute(frame.content.alternative_text().unwrap())
    .replace_all(old="\n", new="&#10;")
    .replace_all(old="\r", new="&#13;")
    .replace_all(old="\t", new="&#9;")
  inner.add(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" role=\"img\" aria-label=\"\{label}\" width=\"\{frame.width}pt\" height=\"\{frame.height}pt\" viewBox=\"0 0 \{frame.width} \{frame.height}\" style=\"vertical-align:middle;overflow:visible\"><defs>",
  )
  let glyphs : Map[String, String] = Map([])
  for primitive in chart.primitives {
    if primitive is Text(text) {
      for run in text.runs {
        for glyph in run.glyphs {
          if glyphs.contains(glyph.outline) {
            continue
          }
          guard output.outlines.get(glyph.outline) is Some(path) else {
            @failure.reject(
              "unsupported-layout", "Chart glyph outline is unavailable",
            )
          }
          let key = "od-chart-\{id}-g\{glyphs.length()}"
          inner.add("<path id=\"\{key}\" d=\"\{property_attribute(path)}\" />")
          glyphs[glyph.outline] = key
        }
      }
    }
  }
  inner.add("</defs>")
  let mut depth = 0
  for index, primitive in chart.primitives {
    match primitive {
      Rectangle(rect) =>
        inner.add(
          "<rect x=\"\{rect.x}\" y=\"\{rect.y}\" width=\"\{rect.width}\" height=\"\{rect.height}\" fill=\"#\{rect.color}\" />",
        )
      Stroke(rect, color, width) =>
        inner.add(
          "<rect x=\"\{rect.x}\" y=\"\{rect.y}\" width=\"\{rect.width}\" height=\"\{rect.height}\" fill=\"none\" stroke=\"#\{color}\" stroke-width=\"\{width}\" />",
        )
      Path(path, fill, stroke, width, pen) => {
        pen.validate()
        let fill = if fill.is_empty() { "none" } else { "#" + fill }
        let stroke = if stroke.is_empty() { "none" } else { "#" + stroke }
        let dash = if pen.dash.is_empty() {
          "none"
        } else {
          pen.dash.map(value => value.to_string()).join(" ")
        }
        inner.add(
          "<path d=\"\{markup_svg_path(path)}\" fill=\"\{fill}\" stroke=\"\{stroke}\" stroke-width=\"\{width}\" fill-opacity=\"\{pen.fillAlpha}\" stroke-opacity=\"\{pen.strokeAlpha}\" stroke-dasharray=\"\{dash}\" stroke-linecap=\"\{["butt", "round", "square"][pen.cap]}\" stroke-linejoin=\"\{["miter", "round", "bevel"][pen.join]}\" stroke-miterlimit=\"\{pen.miter}\" />",
        )
      }
      Text(text) =>
        for run in text.runs {
          inner.add(
            "<g fill=\"#\{run.color}\" transform=\"translate(\{run.x} \{run.baseline})\">",
          )
          for glyph in run.glyphs {
            inner.add(
              "<use href=\"#\{glyphs[glyph.outline]}\" transform=\"translate(\{glyph.x} \{glyph.y}) scale(\{glyph.scale} \{-glyph.scale})\" />",
            )
          }
          inner.add("</g>")
        }
      Transform(m) => {
        inner.add(
          "<g transform=\"matrix(\{m.a} \{m.b} \{m.c} \{m.d} \{m.e} \{m.f})\">",
        )
        depth += 1
      }
      Clip(rect) => {
        let key = "od-chart-\{id}-c\{index}"
        inner.add(
          "<defs><clipPath id=\"\{key}\" clipPathUnits=\"userSpaceOnUse\"><rect x=\"\{rect.x}\" y=\"\{rect.y}\" width=\"\{rect.width}\" height=\"\{rect.height}\" /></clipPath></defs><g clip-path=\"url(#\{key})\">",
        )
        depth += 1
      }
      Restore => {
        guard depth > 0 else {
          @failure.reject("invalid-drawing", "Unbalanced chart markup state")
        }
        inner.add("</g>")
        depth -= 1
      }
      _ =>
        @failure.reject(
          "unsupported-output", "Unsupported chart markup primitive",
        )
    }
  }
  guard depth == 0 else {
    @failure.reject("invalid-drawing", "Unbalanced chart markup state")
  }
  inner.add("</svg>")
  inner.builder.to_string()
}
