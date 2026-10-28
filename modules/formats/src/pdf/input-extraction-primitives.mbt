///|
fn extracted_primitives(
  display : PageDisplay,
  data : PdfExtractionData,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let primitives : Array[@layout.PositionedPrimitive] = []
  let styles : Array[@layout.DrawStyle] = []
  let mut style = @layout.DrawStyle::default()
  for index, command in display.region.commands {
    match command {
      Style(value) => style = value
      Transform(value) => {
        styles.push(style)
        primitives.push(@layout.Transform(value))
      }
      ClipRect(value) => {
        styles.push(style)
        primitives.push(@layout.Clip(value))
      }
      ClipPath(path, evenOdd) => {
        styles.push(style)
        primitives.push(@layout.ClipPath(path.copy(), evenOdd))
      }
      Restore => {
        guard styles.pop() is Some(previous) else {
          @failure.reject(
            "protected-content", "Extracted drawing scopes are unbalanced",
          )
        }
        style = previous
        primitives.push(@layout.Restore)
      }
      FillRect(fill) => primitives.push(@layout.Rectangle(fill))
      StrokeRect(rect, color, width) =>
        primitives.push(@layout.Stroke(rect, color, width))
      Path(path, fill, stroke, width) => {
        if data.pathCommands.get(index) is Some(record) {
          data.paths[record] = {
            ..data.paths[record],
            primitive: primitives.length(),
          }
        }
        primitives.push(
          @layout.Path(path.copy(), fill, stroke, width, {
            fillAlpha: style.fillAlpha,
            strokeAlpha: style.strokeAlpha,
            dash: style.dash.copy(),
            cap: style.cap,
            join: style.join,
            miter: style.miter,
          }),
        )
      }
      Image(image) => {
        if data.imageCommands.get(index) is Some(record) {
          data.images[record] = {
            ..data.images[record],
            primitive: primitives.length(),
          }
        }
        primitives.push(@layout.Image(image, style.fillAlpha))
      }
      Glyphs(_, _, _, glyphs) => {
        guard glyphs is [glyph] && data.glyphCommands.get(index) is Some(record) else {
          @failure.reject(
            "protected-content", "Extracted glyph has no exact source mapping",
          )
        }
        let item = data.glyphs[record]
        guard item.fontIndex >= 0 else {
          @failure.reject(
            "protected-content", "Extracted glyph has no source font",
          )
        }
        primitives.push(
          @layout.Transform({ a: 1, b: 0, c: 0, d: -1, e: 0, f: 0, }),
        )
        data.glyphs[record] = { ..item, primitive: primitives.length(), }
        primitives.push(
          @layout.Text({
            text: item.encodedText,
            runs: [
              {
                color: item.color,
                text: item.encodedText,
                x: 0,
                baseline: 0,
                glyphs: [
                  {
                    id: item.glyph,
                    cluster: 0,
                    font: item.fontIndex,
                    outline: glyph.outline,
                    x: glyph.x,
                    y: -glyph.y,
                    scale: glyph.scaleX,
                    advance: 0,
                    yAdvance: 0,
                    xOffset: 0,
                    yOffset: 0,
                  },
                ],
              },
            ],
          }),
        )
        primitives.push(@layout.Restore)
      }
      _ =>
        @failure.reject(
          "protected-content", "Drawing command cannot be reconstructed by the native PDF writer",
        )
    }
  }
  guard styles.is_empty() else {
    @failure.reject(
      "protected-content", "Extracted drawing scopes are unbalanced",
    )
  }
  primitives
}

///|
/// Extract native page data without changing active selection, retained views,
/// history, or revision. JPEG samples may be supplied from the validated host
/// decode cache; encoded JPEG bytes alone are never presented as clean pixels.
pub fn PdfSession::extract_page(
  self : PdfSession,
  revision : Int32,
  id : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded? : @layout.Images,
) -> PdfExtraction raise @failure.Failure {
  self.check(revision)
  let resources = @layout.Images::new()
  let display = self.build_display(
    id,
    supplied,
    profile,
    resources,
    extract=true,
  )
  errdefer {
    display.probe.close()
    resources.clear()
  }
  pdf_bound(self.budget, () => {
    guard display.extraction is Some(data) else {
      abort("Expected requested PDF extraction data")
    }
    for index, image in data.images {
      if image.jpeg is Some(_) {
        let pixels = match decoded {
          Some(cache) => Some(cache.get(image.key)) catch { _ => None }
          None => None
        }
        let pixels = if pixels is Some(_) {
          pixels
        } else {
          let mut found : @layout.ImageResource? = None
          for _, view in self.views {
            if view.page == id && view.revision == revision {
              if (Some(view.resources.get(image.key)) catch { _ => None })
                is Some(pixels) {
                found = Some(pixels)
                break
              }
            }
          }
          found
        }
        if pixels is Some(pixels) &&
          pixels.width == image.pixelWidth &&
          pixels.height == image.pixelHeight {
          resources.add(image.key, pixels.width, pixels.height, pixels.rgba)
          data.images[index] = { ..image, rgba: pixels.rgba, jpeg: None, }
        }
      }
    }
    let primitives = extracted_primitives(display, data)
    {
      page: id,
      revision,
      width: display.region.width,
      height: display.region.height,
      text: display.text,
      textComplete: display.textComplete,
      displayComplete: display.displayComplete,
      diagnostics: display.diagnostics.copy(),
      glyphs: data.glyphs,
      images: data.images,
      paths: data.paths,
      primitives,
      probe: display.probe,
      resources,
    }
  })
}
