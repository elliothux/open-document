///|
/// Export the exact preview glyph positions. PDF has no text layout authority.
pub fn write(
  layout : @layout.PositionedDocument,
  probe : @layout.TextProbe,
  images : @layout.Images,
  output_limit : Int,
) -> Bytes raise @failure.Failure {
  guard !layout.pages.is_empty() && output_limit > 0 && output_limit <= 67108864 else {
    @failure.reject(
      "invalid-budget", "Invalid PDF output budget or empty layout",
    )
  }
  let fonts = collect_fonts(layout)
  let sources : Map[Int, Bytes] = Map([])
  for index, _ in fonts {
    sources[index] = probe.font_bytes(index)
  }
  try {
    let document = @pdflite.pdf_document_empty()
    let resources : Array[(String, @syntax.PdfObject)] = []
    for index, subset in fonts {
      resources.push(
        (
          "F\{index}",
          @syntax.PdfIndirect(
            install_font(
              document,
              subset,
              sources[index],
              index,
              layout.fonts[index],
              subset.cids.map(cid => {
                probe.glyph_width(index, cid.glyph.reinterpret_as_uint())
              }),
            ),
          ),
        ),
      )
    }
    let pages : Array[@page.PdfPage] = []
    let installed_images : Map[String, (String, @syntax.PdfObject)] = Map([])
    let mut content_bytes = 0
    for frame in layout.pages {
      let ops : Array[@content.PdfContentOp] = []
      let image_objects : Array[(String, @syntax.PdfObject)] = []
      let alpha_states : Map[String, (String, @syntax.PdfObject)] = Map([])
      let mut scopes = 0
      for primitive in frame.primitives {
        match primitive {
          Transform(matrix) => {
            ops.push(@content.Op_q)
            scopes += 1
            // Conjugate the top-left coordinate transform by the PDF page flip.
            ops.push(
              @content.Op_cm({
                a: matrix.a,
                b: -matrix.b,
                c: -matrix.c,
                d: matrix.d,
                e: matrix.c * frame.height + matrix.e,
                f: frame.height * (1 - matrix.d) - matrix.f,
              }),
            )
          }
          Clip(clip) => {
            ops.push(@content.Op_q)
            scopes += 1
            ops.push(
              @content.Op_re(
                clip.x,
                frame.height - clip.y - clip.height,
                clip.width,
                clip.height,
              ),
            )
            ops.push(@content.Op_W)
            ops.push(@content.Op_n)
          }
          Restore => {
            guard scopes > 0 else {
              @failure.reject("invalid-drawing", "Unbalanced PDF scope")
            }
            scopes -= 1
            ops.push(@content.Op_Q)
          }
          Path(path, fill, stroke, width, pen) => {
            pen.validate()
            ops.push(@content.Op_q)
            ops.push(@content.Op_d(pen.dash, 0))
            ops.push(@content.Op_J(pen.cap))
            ops.push(@content.Op_j(pen.join))
            ops.push(@content.Op_M(pen.miter))
            if !fill.is_empty() {
              ops.push(
                @content.Op_rg(
                  channel(fill, 0),
                  channel(fill, 2),
                  channel(fill, 4),
                ),
              )
            }
            if !stroke.is_empty() {
              ops.push(
                @content.Op_RG(
                  channel(stroke, 0),
                  channel(stroke, 2),
                  channel(stroke, 4),
                ),
              )
              ops.push(@content.Op_w(width))
            }
            for segment in path {
              match segment {
                Move(x, y) => ops.push(@content.Op_m(x, frame.height - y))
                Line(x, y) => ops.push(@content.Op_l(x, frame.height - y))
                Cubic(x1, y1, x2, y2, x, y) =>
                  ops.push(
                    @content.Op_c(
                      x1,
                      frame.height - y1,
                      x2,
                      frame.height - y2,
                      x,
                      frame.height - y,
                    ),
                  )
                Close => ops.push(@content.Op_h)
              }
            }
            if !fill.is_empty() && !stroke.is_empty() {
              ops.push(@content.Op_B)
            } else if !fill.is_empty() {
              ops.push(@content.Op_f)
            } else if !stroke.is_empty() {
              ops.push(@content.Op_S)
            } else {
              ops.push(@content.Op_n)
            }
            ops.push(@content.Op_Q)
          }
          Rectangle(fill) => {
            ops.push(
              @content.Op_rg(
                channel(fill.color, 0),
                channel(fill.color, 2),
                channel(fill.color, 4),
              ),
            )
            ops.push(
              @content.Op_re(
                fill.x,
                frame.height - fill.y - fill.height,
                fill.width,
                fill.height,
              ),
            )
            ops.push(@content.Op_f)
          }
          Stroke(rect, color, width) => {
            ops.push(@content.Op_w(width))
            ops.push(
              @content.Op_RG(
                channel(color, 0),
                channel(color, 2),
                channel(color, 4),
              ),
            )
            ops.push(
              @content.Op_re(
                rect.x,
                frame.height - rect.y - rect.height,
                rect.width,
                rect.height,
              ),
            )
            ops.push(@content.Op_S)
          }
          Image(image, opacity) => {
            guard !opacity.is_nan() &&
              !opacity.is_inf() &&
              opacity >= 0 &&
              opacity <= 1 else {
              @failure.reject(
                "invalid-drawing", "Invalid positioned image opacity",
              )
            }
            let entry = if installed_images.get(image.key) is Some(entry) {
              entry
            } else {
              let source = images.get(image.key)
              guard source.rgba.length() <= output_limit else {
                @failure.reject(
                  "limit-exceeded", "PDF image exceeds output budget",
                )
              }
              let id = "I\{installed_images.length()}"
              let rgb : Array[Byte] = []
              let alpha : Array[Byte] = []
              for pixel in 0..<(source.width * source.height) {
                rgb.push(source.rgba[pixel * 4])
                rgb.push(source.rgba[pixel * 4 + 1])
                rgb.push(source.rgba[pixel * 4 + 2])
                alpha.push(source.rgba[pixel * 4 + 3])
              }
              let common : Array[(String, @syntax.PdfObject)] = [
                ("Type", tag("XObject")),
                ("Subtype", tag("Image")),
                ("Width", @syntax.PdfInteger(source.width)),
                ("Height", @syntax.PdfInteger(source.height)),
                ("BitsPerComponent", @syntax.PdfInteger(8)),
                ("Interpolate", @syntax.PdfBoolean(true)),
              ]
              let mask = document.add_object(
                stream(
                  Bytes::from_array(alpha),
                  common + [("ColorSpace", tag("DeviceGray"))],
                ),
              )
              let object = document.add_object(
                stream(
                  Bytes::from_array(rgb),
                  common +
                  [
                    ("ColorSpace", tag("DeviceRGB")),
                    ("SMask", @syntax.PdfIndirect(mask)),
                  ],
                ),
              )
              let entry = (id, @syntax.PdfIndirect(object))
              installed_images[image.key] = entry
              entry
            }
            if !image_objects.iter().any(item => item.0 == entry.0) {
              image_objects.push(entry)
            }
            ops.push(@content.Op_q)
            if opacity != 1 {
              let key = opacity.to_string()
              let state = alpha_states
                .get(key)
                .unwrap_or_else(() => {
                  let state = (
                    "A\{alpha_states.length()}",
                    dict([
                      ("Type", tag("ExtGState")),
                      ("ca", @syntax.PdfReal(opacity)),
                    ]),
                  )
                  alpha_states[key] = state
                  state
                })
              ops.push(@content.Op_gs(name(state.0)))
            }
            ops.push(
              @content.Op_cm({
                a: image.width,
                b: 0,
                c: 0,
                d: image.height,
                e: image.x,
                f: frame.height - image.y - image.height,
              }),
            )
            ops.push(@content.Op_Do(name(entry.0)))
            ops.push(@content.Op_Q)
          }
          Text(line) => {
            if line.text.is_empty() {
              continue
            }
            let actual = dict([
              ("ActualText", @syntax.PdfString(utf16_bytes(line.text))),
            ])
            ops.push(@content.Op_BDC(name("Span"), actual))
            for run in line.runs {
              let color = run.color
              ops.push(
                @content.Op_rg(
                  channel(color, 0),
                  channel(color, 2),
                  channel(color, 4),
                ),
              )
              for index, glyph in run.glyphs {
                let subset = fonts[glyph.font]
                let cid = subset.codes[cid_key(
                    glyph.id.reinterpret_as_int(),
                    glyph_text(run, index),
                  )]
                ops.push(@content.Op_BT)
                ops.push(
                  @content.Op_Tf(
                    name("F\{glyph.font}"),
                    glyph.scale * layout.fonts[glyph.font].upem.to_double(),
                  ),
                )
                ops.push(
                  @content.Op_Tm({
                    a: 1,
                    b: 0,
                    c: 0,
                    d: 1,
                    e: run.x + glyph.x,
                    f: frame.height - run.baseline - glyph.y,
                  }),
                )
                ops.push(
                  @content.Op_Tj(
                    Bytes::from_array([
                      (cid >> 8).to_byte(),
                      (cid & 255).to_byte(),
                    ]),
                  ),
                )
                ops.push(@content.Op_ET)
              }
            }
            ops.push(@content.Op_EMC)
          }
        }
      }
      guard scopes == 0 else {
        @failure.reject("invalid-drawing", "Unclosed PDF scope")
      }
      let bytes = @pdflite.pdf_content_bytes_of_ops(ops)
      content_bytes += bytes.length()
      guard content_bytes <= output_limit else {
        @failure.reject("limit-exceeded", "PDF content exceeds output budget")
      }
      let page_resources = [
        ("Font", dict(resources)),
        ("XObject", dict(image_objects)),
      ]
      if !alpha_states.is_empty() {
        page_resources.push(
          ("ExtGState", dict(alpha_states.values().to_array())),
        )
      }
      pages.push({
        content: [stream(bytes, [])],
        mediabox: @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
          @syntax.PdfReal(frame.width),
          @syntax.PdfReal(frame.height),
        ]),
        resources: dict(page_resources),
        rotate: @page.Rotate0,
        rest: dict([]),
      })
    }
    ignore(document.add_root(document.add_pagetree(pages), []))
    // Preflight payload bytes; the final check includes xref and trailer overhead.
    let mut estimate = 0
    document.iter_objects((_, object) => {
      estimate += @pdflite.pdf_write_object(object).length()
      guard estimate <= output_limit else {
        @failure.reject("limit-exceeded", "PDF objects exceed output budget")
      }
    })
    let bytes = @pdflite.pdf_write_document(document)
    guard bytes.length() <= output_limit else {
      @failure.reject("limit-exceeded", "PDF output exceeds budget")
    }
    bytes
  } catch {
    @failure.Failure(..) as error => raise error
    error => @failure.reject("pdf-export-failed", error.to_string())
  }
}
