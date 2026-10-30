///|
fn presentation_line_height(
  line : @layout.Line,
  nominal_size : Double,
  spacing : @layout.LineSpacing,
) -> Double {
  match spacing {
    Auto(_) => {
      let mut size = 0.0
      for run in line.runs {
        size = size.max(run.nominalSize)
      }
      for run in line.marker {
        size = size.max(run.nominalSize)
      }
      line.height.max((if size > 0 { size } else { nominal_size }) * 1.2)
    }
    _ => line.height
  }
}

///|
fn measure_text(
  object : Object,
  geometry : Geometry,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  scale : Double,
) -> (Array[@layout.Line], Double) raise @failure.Failure {
  let lines : Array[@layout.Line] = []
  let mut top = object.body.top
  let mut offset = 0
  let width = text_column_width(object.body, geometry.width)
  for index, paragraph in object.paragraphs {
    let spans : Array[@layout.Span] = []
    for run in paragraph.runs {
      for (style, text) in run.parts {
        spans.push({
          node: run.source.map(item => item.node.id).unwrap_or(0),
          text: text.replace_all(old="\u2028", new="\n"),
          drawing: run.math.map(formula => {
            width: 0,
            height: 0,
            anchor: None,
            content: @layout.Math(
              @layout.MathFormula::new(
                formula.expression,
                { ..formula.style, size: formula.style.size * scale, },
                display=formula.display,
              ),
            ),
          }),
          field: "",
          style: { ..style, size: style.size * scale, },
        })
      }
    }
    let spacing : @layout.LineSpacing = match paragraph.spacing {
      Exact(value) => Exact(value * scale)
      AtLeast(value) => AtLeast(value * scale)
      // ONLYOFFICE applies the reduction before merging explicit paragraph spacing.
      Auto(value) => {
        let explicit = paragraph.source.child("pPr").bind(p => p.child("lnSpc"))
          is Some(_)
        Auto(
          (value -
          (if explicit { 0.0 } else { object.body.lineSpaceReduction * 240 })).max(
            0,
          ),
        )
      }
    }
    let flow : @layout.Paragraph = {
      id: index,
      container: 0,
      spans,
      nominalSize: spans[0].style.size,
      frame: None,
      defaultTab: paragraph.default_tab,
      tabs: paragraph.tabs.map(t => {
        position: t.position,
        align: t.align,
        leader: "none",
      }),
      decimalSymbol: ".",
      expandSoftBreak: true,
      left: paragraph.left,
      right: paragraph.right,
      first: paragraph.first,
      align: if paragraph.align == "justify" {
        "both"
      } else if paragraph.rtl && paragraph.align == "left" {
        "right"
      } else if paragraph.rtl && paragraph.align == "right" {
        "left"
      } else {
        paragraph.align
      },
      before: 0,
      after: 0,
      line: spacing,
      pageBreakBefore: false,
      keepLines: false,
      keepNext: false,
      widowControl: false,
      rtl: paragraph.rtl,
      marker: if paragraph.bullet.is_empty() {
        None
      } else {
        Some({
          text: paragraph.bullet,
          numbering: None,
          style: {
            ..paragraph.bullet_style,
            size: paragraph.bullet_style.size * scale,
          },
          align: "left",
          suffix: "tab",
        })
      },
      readOnlyReason: object.text_reason,
    }
    let measured = probe.paragraph_lines(
      flow,
      profile,
      width,
      object.body.wrap,
      baseLevel=if paragraph.rtl { 1 } else { 0 },
    )
    if index > 0 || object.body.firstLastSpacing {
      top += paragraph.before.points(
        presentation_line_height(measured[0], flow.nominalSize, spacing),
      )
    }
    for line in measured {
      let mut visible_end = line.text.length()
      while visible_end > 0 &&
            [9, 32].contains(line.text[visible_end - 1].to_int()) {
        visible_end -= 1
      }
      let trailing = if visible_end < line.text.length() {
        line.carets
        .iter()
        .find_first(c => c.offset == line.start + visible_end)
        .map(c => if paragraph.rtl { c.before } else { line.width - c.before })
        .unwrap_or(0)
      } else {
        0.0
      }
      let alignment = trailing *
        (match paragraph.align {
          "center" => 0.5
          "right" => 1.0
          _ => 0.0
        }) *
        (if paragraph.rtl { -1.0 } else { 1.0 })
      let left = line.x + object.body.left + alignment
      // Presentation single spacing reserves at least 120% of the nominal size.
      // Preserve the font's ascent/descent proportions when adding that leading.
      let height = presentation_line_height(line, flow.nominalSize, spacing)
      let advance = match spacing {
        Auto(value) => height * value / 240
        _ => line.height
      }
      lines.push({
        ..line,
        start: line.start + offset,
        end: line.end + offset,
        x: left,
        y: top,
        height: advance,
        areaX: object.body.left,
        areaWidth: width,
        runs: line.runs.map(run => {
          ..run,
          x: run.x + left,
          baseline: run.baseline * height / line.height + top,
        }),
        marker: line.marker.map(run => {
          ..run,
          x: run.x + left,
          baseline: run.baseline * height / line.height + top,
        }),
        drawings: line.drawings.map(drawing => {
          ..drawing,
          start: drawing.start + offset,
          x: drawing.x + left,
          y: drawing.y + top,
        }),
        carets: line.carets.map(caret => {
          ..caret,
          offset: caret.offset + offset,
        }),
      })
      top += advance
    }
    if index + 1 < object.paragraphs.length() || object.body.firstLastSpacing {
      top += paragraph.after.points(
        presentation_line_height(
          measured.last().unwrap(),
          flow.nominalSize,
          spacing,
        ),
      )
    }
    offset += paragraph.runs
      .iter()
      .fold(init=0, (sum, run) => sum + run.text.length()) +
      1
  }
  text_columns(lines, object, geometry, top + object.body.bottom)
}

///|
fn fit_text(
  object : Object,
  geometry : Geometry,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  recalculate~ : Bool = false,
) -> (Array[@layout.Line], Double, String, @layout.Matrix) raise @failure.Failure {
  if object.paragraphs.is_empty() {
    return ([], 1, "", @layout.Matrix::identity())
  }
  let (body, geometry, direction) = object.text_plane(geometry)
  let object = {
    ..object,
    body: if recalculate {
      { ..body, fontScale: None, lineSpaceReduction: 0, }
    } else {
      body
    },
  }
  let mut scale = if object.body.fit == "shrink" {
    object.body.fontScale.unwrap_or(1)
  } else {
    1.0
  }
  let mut measured = measure_text(object, geometry, probe, profile, scale) catch {
    @failure.Failure(code="layout-overflow", ..) if object.body.fit == "shrink" =>
      ([], geometry.height + 1)
    @failure.Failure(code="layout-overflow", ..) =>
      measure_text(
        { ..object, body: { ..object.body, wrap: false, }, },
        geometry,
        probe,
        profile,
        scale,
      )
    error => raise error
  }
  let fits = fn(result : (Array[@layout.Line], Double)) {
    result.1 <= geometry.height &&
    result.0.all(line => line.width <= line.areaWidth + 0.01)
  }
  if object.body.fit == "shrink" &&
    object.body.fontScale is None &&
    !fits(measured) {
    // ONLYOFFICE Shape.checkExtentsByDocContent tries five-percent font steps
    // and reduces inherited line spacing by one fifth of the font reduction.
    let minimum = if placeholder(object.source)
      .map(value => ["title", "ctrTitle"].contains(value.0))
      .unwrap_or(false) {
      90
    } else {
      25
    }
    for percent = 95; percent >= minimum; percent = percent - 5 {
      let trial = percent.to_double() / 100
      let candidate = {
        ..object,
        body: { ..object.body, lineSpaceReduction: 0.2 * (1 - trial), },
      }
      let result = measure_text(candidate, geometry, probe, profile, trial) catch {
        @failure.Failure(code="layout-overflow", ..) =>
          ([], geometry.height + 1)
        error => raise error
      }
      scale = trial
      measured = result
      if fits(measured) {
        break
      }
    }
  }
  // An empty unbulleted paragraph reserves a caret without visible document text.
  let blank = object.paragraphs.length() == 1 &&
    object.paragraphs[0].bullet.is_empty() &&
    object.text().is_empty()
  let diagnostic = if (!blank && measured.1 > geometry.height + 0.01) ||
    measured.0.any(line => line.width > line.areaWidth + 0.01) {
    "Text exceeds the fixed frame"
  } else {
    ""
  }
  let free = geometry.height - measured.1
  let dy = match object.body.anchor {
    "ctr" => free / 2
    "b" => free
    _ => 0.0
  }
  (
    measured.0.map(line => {
      ..line,
      y: line.y + dy,
      runs: line.runs.map(run => { ..run, baseline: run.baseline + dy, }),
      marker: line.marker.map(run => { ..run, baseline: run.baseline + dy, }),
      drawings: line.drawings.map(drawing => { ..drawing, y: drawing.y + dy, }),
    }),
    scale,
    diagnostic,
    direction.then(body.text_rotation(geometry.width, measured.1, dy)),
  )
}

///|
fn paint_slide(
  slide : Slide,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  tile_sizes : Map[String, (Int32, Int32)],
  parts~ : Array[(String, Array[@layout.PositionedPrimitive])]? = None,
  text_fit_diagnostics~ : Bool = true,
) -> (@layout.PositionedPage, Array[TextGeometry], Array[String]) raise @failure.Failure {
  let primitives : Array[@layout.PositionedPrimitive] = []
  if slide.background is Linear(stops, _, _) &&
    stops.any(stop => stop.opacity != 1) {
    primitives.push(Rectangle({ x: 0, y: 0, width, height, color: "ffffff", }))
  }
  primitives.append(slide.background.paint(width, height, tile_sizes~))
  if parts is Some(parts) {
    parts.push(("", primitives.copy()))
  }
  let texts : Array[TextGeometry] = []
  let fonts = probe.font_info()
  let diagnostics = slide.diagnostics.copy()
  let mut units = 0
  for object in slide.objects {
    if object.kind == "group" {
      continue
    }
    guard object.geometry is Some(geometry) else { continue }
    let start = primitives.length()
    primitives.push(Transform(geometry.matrix))
    if !object.diagnostic.is_empty() {
      primitives.push(
        Rectangle({
          x: 0,
          y: 0,
          width: geometry.width,
          height: geometry.height,
          color: "eeeeee",
        }),
      )
      primitives.push(
        Stroke(
          { x: 0, y: 0, width: geometry.width, height: geometry.height, },
          "bb4444",
          1,
        ),
      )
    } else if object.chart is Some(chart) {
      let commands = chart.paint(
        geometry.width,
        geometry.height,
        probe,
        profile,
      )
      for command in commands {
        if command is @layout.Text(text) {
          units += text.runs.fold(init=0, (sum, run) => {
            sum + run.glyphs.length()
          })
        }
      }
      guard units <= 262144 else {
        @failure.reject("limit-exceeded", "Slide glyphs exceed budget")
      }
      primitives.append(commands)
    } else if object.table is Some(_) {
      let transforms = Map([])
      let (commands, lines, warnings, glyphs) = object.paint_table(
        probe,
        profile,
        transforms~,
      )
      primitives.append(commands)
      texts.push({
        object: object.id,
        matrix: geometry.matrix,
        lines,
        transforms,
      })
      diagnostics.append(warnings)
      units += glyphs
      guard units <= 262144 else {
        @failure.reject("limit-exceeded", "Slide glyphs exceed budget")
      }
    } else {
      if !object.polyline.is_empty() || curved_connector(object.preset) {
        primitives.push(
          Path(
            object.line_path(geometry),
            "",
            object.stroke,
            object.line_width,
            {
              fillAlpha: 1,
              strokeAlpha: object.stroke_alpha,
              dash: dash_pattern(object.dash).map(v => v * object.line_width),
              cap: line_cap_code(object.cap),
              join: if object.join == "round" {
                1
              } else if object.join == "bevel" {
                2
              } else {
                0
              },
              miter: object.miter,
            },
          ),
        )
        primitives.append(object.draw_line_ends(geometry))
      } else if object.kind == "image" && object.image is Some(_) {
        if object.preset == "rect" {
          primitives.push(
            Clip({ x: 0, y: 0, width: geometry.width, height: geometry.height, }),
          )
        } else {
          primitives.push(
            ClipPath(
              shape_path(
                object.preset,
                geometry.width,
                geometry.height,
                object.adjustments,
              ),
              false,
            ),
          )
        }
        if object.tile is Some(tile) {
          primitives.append(
            tile.paint(
              object.image.unwrap(),
              object.opacity,
              geometry.width,
              geometry.height,
              tile_sizes[object.image.unwrap()],
            ),
          )
        } else {
          primitives.append(object.image_primitives(geometry))
        }
        primitives.push(Restore)
      } else if object.has_fill() || !object.stroke.is_empty() {
        let path = shape_path(
          object.preset,
          geometry.width,
          geometry.height,
          object.adjustments,
        )
        if object.image is Some(_) && geometry.width > 0 && geometry.height > 0 {
          primitives.push(ClipPath(path, false))
          if object.tile is Some(_) {
            primitives.append(
              object.tile
              .unwrap()
              .paint(
                object.image.unwrap(),
                object.opacity,
                geometry.width,
                geometry.height,
                tile_sizes[object.image.unwrap()],
              ),
            )
          } else {
            primitives.append(object.image_primitives(geometry))
          }
          primitives.push(Restore)
        } else if object.gradient is Some(gradient) &&
          geometry.width > 0 &&
          geometry.height > 0 {
          primitives.push(ClipPath(path, false))
          primitives.append(gradient.paint(geometry.width, geometry.height))
          primitives.push(Restore)
        }
        primitives.push(
          Path(path, object.fill, object.stroke, object.line_width, {
            fillAlpha: object.fill_alpha,
            strokeAlpha: object.stroke_alpha,
            dash: dash_pattern(object.dash).map(v => v * object.line_width),
            cap: line_cap_code(object.cap),
            join: if object.join == "round" {
              1
            } else if object.join == "bevel" {
              2
            } else {
              0
            },
            miter: object.miter,
          }),
        )
        primitives.append(object.draw_line_ends(geometry))
      }
      let (lines, _, diagnostic, rotation) = fit_text(
        object, geometry, probe, profile,
      ) catch {
        @failure.Failure(code="layout-overflow", message~, ..) =>
          ([], 1.0, message, @layout.Matrix::identity())
        error => raise error
      }
      if !diagnostic.is_empty() && (text_fit_diagnostics || lines.is_empty()) {
        diagnostics.push(object.id + ":" + diagnostic)
        if lines.is_empty() {
          primitives.push(
            Stroke(
              { x: 0, y: 0, width: geometry.width, height: geometry.height, },
              "bb4444",
              1,
            ),
          )
        }
      }
      let (_, frame, _) = object.text_plane(geometry)
      texts.push({
        object: object.id,
        matrix: geometry.matrix.then(rotation),
        lines,
        transforms: Map([]),
      })
      if !lines.is_empty() {
        let (clip_matrix, clip) = object.text_clip(geometry)
        let clipped = object.body.clipHorizontal || object.body.clipVertical
        if clipped {
          let inverse = geometry.matrix.then(clip_matrix).inverse()
          let corners = [
            (0.0, 0.0),
            (width, 0.0),
            (0.0, height),
            (width, height),
          ].map(p => inverse.point(p.0, p.1))
          let left = corners
            .iter()
            .map(p => p.0)
            .fold(init=corners[0].0, (a, b) => a.min(b))
          let top = corners
            .iter()
            .map(p => p.1)
            .fold(init=corners[0].1, (a, b) => a.min(b))
          let right = corners
            .iter()
            .map(p => p.0)
            .fold(init=corners[0].0, (a, b) => a.max(b))
          let bottom = corners
            .iter()
            .map(p => p.1)
            .fold(init=corners[0].1, (a, b) => a.max(b))
          primitives.push(Transform(clip_matrix))
          // An unclipped axis spans the whole slide, including transformed groups.
          primitives.push(
            Clip({
              x: if object.body.clipHorizontal {
                clip.x
              } else {
                left
              },
              y: if object.body.clipVertical {
                clip.y
              } else {
                top
              },
              width: if object.body.clipHorizontal {
                clip.width
              } else {
                right - left
              },
              height: if object.body.clipVertical {
                clip.height
              } else {
                bottom - top
              },
            }),
          )
          primitives.push(Transform(clip_matrix.inverse().then(rotation)))
        } else {
          primitives.push(Transform(rotation))
        }
        for line in lines {
          if object.body.columns > 1 {
            primitives.push(
              Clip({
                x: line.areaX,
                y: 0,
                width: line.areaWidth,
                height: frame.height,
              }),
            )
          }
          // DrawingML overflow is controlled by the text frame rather than line spacing.
          let commands = { ..line, clip: false, }.positioned(fonts, frame.width)
          for command in commands {
            if command is @layout.Text(text) {
              units += text.runs.fold(init=0, (sum, run) => {
                sum + run.glyphs.length()
              })
            }
          }
          primitives.append(commands)
          if object.body.columns > 1 {
            primitives.push(Restore)
          }
          guard units <= 262144 else {
            @failure.reject("limit-exceeded", "Slide glyphs exceed budget")
          }
        }
        primitives.push(Restore)
        if clipped {
          primitives.push(Restore)
          primitives.push(Restore)
        }
      }
    }
    primitives.push(Restore)
    if parts is Some(parts) {
      parts.push((object.id, primitives[start:].to_owned()))
    }
  }
  ({ width, height, primitives, }, texts, diagnostics)
}

///|
pub fn Session::layout(
  self : Session,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
) -> Json raise @failure.Failure {
  let slide = self.current()
  let key = Json::array([
    Json(self.revision),
    Json(slide.tree.part),
    Json(profile),
    Json(probe.font_info()),
  ]).stringify()
  if self.view is Some(view) && view.key == key {
    return view.result
  }
  let (page, texts, diagnostics) = paint_slide(
    slide,
    self.width,
    self.height,
    probe,
    profile,
    self.tile_sizes(slide),
  )
  let document : @layout.PositionedDocument = {
    links: [],
    pages: [page],
    fonts: probe.font_info(),
  }
  let resources : Array[String] = []
  for key in slide.image_keys() {
    if !resources.contains(images.get(key).identity) {
      resources.push(images.get(key).identity)
    }
  }
  guard self.sequence < 2147483647 else {
    @failure.reject("limit-exceeded", "Layout identity exhausted")
  }
  self.sequence += 1
  let result : Json = {
    "id": self.sequence,
    "revision": self.revision,
    "slide": slide.tree.part,
    "regions": document.drawing(images),
    "outlines": probe.outline_resources(),
    "images": resources,
    "diagnostics": diagnostics,
  }
  self.view = Some({
    id: self.sequence,
    key,
    revision: self.revision,
    slide: slide.tree.part,
    texts,
    result,
  })
  result
}

///|
pub fn Session::print_layout(
  self : Session,
  revision : Int32,
  all : Bool,
  hidden : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.PositionedDocument raise @failure.Failure {
  self.check_revision(revision)
  self.check_candidate_idle()
  let pages : Array[@layout.PositionedPage] = []
  let links : Array[@layout.PageLink] = []
  let slides = (if all { self.slides } else { [self.current()] }).filter(slide => {
    !all || hidden || !slide.hidden
  })
  let destinations = Map::from_array(
    slides.mapi((index, slide) => (slide.tree.part, index)),
  )
  let relationships = self.relationships()
  let mut link_work = 0
  let mut primitives = 0
  for slide in slides {
    let (page, texts, diagnostics) = paint_slide(
      slide,
      self.width,
      self.height,
      probe,
      profile,
      self.tile_sizes(slide),
      text_fit_diagnostics=false,
    )
    guard diagnostics.is_empty() else {
      @failure.reject(
        "unsupported-pdf",
        diagnostics.join("; "),
        part=slide.tree.part,
      )
    }
    primitives += page.primitives.length()
    guard primitives <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Presentation PDF primitives exceed budget",
      )
    }
    let (items, work) = self.print_links(
      slide,
      texts,
      pages.length(),
      destinations,
      relationships,
      8388608 - link_work,
    )
    link_work += work
    guard items.length() <= 65536 - links.length() else {
      @failure.reject("limit-exceeded", "Presentation PDF links exceed budget")
    }
    links.append(items)
    pages.push(page)
  }
  guard !pages.is_empty() else {
    @failure.reject("unsupported-pdf", "No slides selected for PDF")
  }
  { pages, fonts: probe.font_info(), links, }
}

///|
pub fn Session::image_keys(
  self : Session,
  all : Bool,
  hidden : Bool,
) -> Array[String] raise @failure.Failure {
  self.check()
  let keys : Array[String] = []
  for slide in (if all { self.slides } else { [self.current()] }) {
    if !all || hidden || !slide.hidden {
      for key in slide.image_keys() {
        if !keys.contains(key) {
          keys.push(key)
        }
      }
    }
  }
  guard keys.length() <= 256 else {
    @failure.reject("limit-exceeded", "Presentation images exceed 256")
  }
  keys
}
