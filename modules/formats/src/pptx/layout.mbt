///|
fn presentation_line_height(
  line : @layout.Line,
  text_height : Double,
  spacing : @layout.LineSpacing,
) -> Double {
  match spacing {
    Auto(_) => {
      let mut height = text_height
      for run in line.marker {
        height = height.max(run.nominalSize * 1.2)
      }
      if line.drawings.is_empty() &&
        line.runs.all(run => run.rise == 0) &&
        line.marker.all(run => run.rise == 0) {
        height
      } else {
        line.height.max(height)
      }
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
  let mut previous_after = 0.0
  let mut offset = 0
  let width = text_column_width(object.body, geometry.width)
  for index, paragraph in object.paragraphs {
    // Native document drawing hides empty list markers while retaining their measured advance.
    let show_marker = paragraph.runs.any(run => !run.text.is_empty())
    let flow = object.paragraph_flow(index, scale)
    let spacing = flow.line
    // Native text rectangles add 0.01 mm before aligning hanging RTL lists.
    let layout_width = if width < 14400 &&
      flow.marker is Some({ suffix: "presentation-rtl", .. }) {
      (width + 0.01 * 72 / 25.4).min(14400)
    } else {
      width
    }
    let measured = probe.paragraph_lines(
      flow,
      profile,
      layout_width,
      object.body.wrap,
      baseLevel=if paragraph.rtl { 1 } else { 0 },
      ligatures=false,
    )
    if index > 0 || object.body.firstLastSpacing {
      let (ascent, descent) = presentation_text_metrics(
        measured[0],
        flow,
        probe,
        profile,
      )
      // Native paragraphs merge adjacent gaps; percentages use natural text height.
      top += (paragraph.before.points(
        presentation_line_height(measured[0], ascent + descent, Auto(240)),
      ) -
      previous_after).max(0)
    }
    for line in measured {
      let left = line.x + object.body.left
      // Native presentations normalize each font before combining line extents.
      let (ascent, descent) = presentation_text_metrics(
        line, flow, probe, profile,
      )
      let height = presentation_line_height(line, ascent + descent, spacing)
      let advance = match spacing {
        Auto(value) => height * value / 240
        _ => line.height
      }
      // Native expanded automatic lines reserve at least three quarters for ascent.
      let natural_baseline = match line.runs.get(0) {
        Some(run) => run.baseline + run.rise
        None =>
          line.marker
          .get(0)
          .map(run => run.baseline + run.rise)
          .unwrap_or(line.height * 0.8)
      }
      let automatic_baseline = if line.drawings.is_empty() &&
        line.runs.all(run => run.rise == 0) &&
        line.marker.all(run => run.rise == 0) {
        ascent * height / (ascent + descent)
      } else {
        natural_baseline * height / line.height
      }
      let baseline_shift = if spacing is Exact(_) {
        presentation_exact_baseline(line, flow, probe, profile) -
        natural_baseline
      } else {
        // Negative automatic line gaps shift the whole baseline.
        let baseline = if advance > height {
          automatic_baseline.max(advance * 0.75)
        } else {
          automatic_baseline + (advance - height).min(0)
        }
        baseline - natural_baseline * height / line.height
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
          start: run.start + offset,
          x: run.x + left,
          baseline: run.baseline * height / line.height + top + baseline_shift,
        }),
        markerText: if show_marker {
          line.markerText
        } else {
          ""
        },
        marker: line.marker
        .filter(_ => show_marker)
        .map(run => {
          ..run,
          start: run.start + offset,
          x: run.x + left,
          baseline: run.baseline * height / line.height + top + baseline_shift,
        }),
        markerImage: if show_marker {
          line.markerImage.map(image => {
            ..image,
            x: image.x + left,
            y: (image.y + image.height) * height / line.height -
            image.height +
            top +
            baseline_shift,
          })
        } else {
          None
        },
        drawings: line.drawings.map(drawing => {
          ..drawing,
          start: drawing.start + offset,
          x: drawing.x + left,
          y: drawing.y + top + baseline_shift,
        }),
        carets: line.carets.map(caret => {
          ..caret,
          offset: caret.offset + offset,
        }),
      })
      top += advance
    }
    if index + 1 < object.paragraphs.length() || object.body.firstLastSpacing {
      let (ascent, descent) = presentation_text_metrics(
        measured.last().unwrap(),
        flow,
        probe,
        profile,
      )
      previous_after = paragraph.after.points(
        presentation_line_height(
          measured.last().unwrap(),
          ascent + descent,
          Auto(240),
        ),
      )
      top += previous_after
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
      { ..body, fontScale: Some(1), lineSpaceReduction: 0, }
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
    result.0.all(line => line.content_width() <= line.areaWidth + 0.01)
  }
  if object.body.fit == "shrink" && recalculate && !fits(measured) {
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
    measured.0.any(line => line.content_width() > line.areaWidth + 0.01) {
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
      markerImage: line.markerImage.map(image => { ..image, y: image.y + dy, }),
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
  for object in fit_diagram_text(slide.objects, probe, profile) {
    if object.kind == "group" {
      continue
    }
    guard object.geometry is Some(geometry) else { continue }
    let start = primitives.length()
    primitives.push(Transform(geometry.matrix))
    if object.shadow_primitive(geometry) is Some(shadow) {
      primitives.push(shadow)
    }
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
              evenOdd: false,
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
      } else if object.metafile is Some(file) {
        units += file.commands.fold(init=0, (sum, command) => {
          let work = match command {
            @layout.Vector(path, _, _, _, _, _) => path.length() * 3
            @layout.Label(text) => text.text.length()
            _ => 0
          }
          sum + work
        })
        guard units <= 262144 else {
          @failure.reject(
            "limit-exceeded", "Slide metafile drawing exceeds budget",
          )
        }
        primitives.append(
          positioned_picture_metafile(
            file,
            geometry,
            object.crop,
            probe,
            profile,
          ),
        )
      } else if object.kind == "image" && object.image is Some(_) {
        if object.preset == "rect" {
          primitives.push(
            Clip({ x: 0, y: 0, width: geometry.width, height: geometry.height, }),
          )
        } else {
          primitives.push(ClipPath(object.shape_path(geometry), false))
        }
        primitives.append(object.image_primitives(geometry, tile_sizes))
        primitives.push(Restore)
      } else if object.has_fill() || !object.stroke.is_empty() {
        let path = object.shape_path(geometry)
        units += path.length() * 3
        guard units <= 262144 else {
          @failure.reject(
            "limit-exceeded", "Slide geometry exceeds drawing budget",
          )
        }
        let fill = if object.custom is Some({ fill: false, .. }) {
          ""
        } else {
          object.fill
        }
        let stroke = if object.custom is Some({ stroke: false, .. }) {
          ""
        } else {
          object.stroke
        }
        if object.has_fill() &&
          object.image is Some(_) &&
          geometry.width > 0 &&
          geometry.height > 0 {
          primitives.push(ClipPath(path, false))
          primitives.append(object.image_primitives(geometry, tile_sizes))
          primitives.push(Restore)
        } else if object.has_fill() &&
          object.gradient is Some(gradient) &&
          geometry.width > 0 &&
          geometry.height > 0 {
          primitives.push(ClipPath(path, false))
          let bounds = object.fill_bounds(geometry)
          if bounds.x != 0 || bounds.y != 0 {
            primitives.push(
              Transform({
                ..@layout.Matrix::identity(),
                e: bounds.x,
                f: bounds.y,
              }),
            )
          }
          primitives.append(gradient.paint(bounds.width, bounds.height))
          if bounds.x != 0 || bounds.y != 0 {
            primitives.push(Restore)
          }
          primitives.push(Restore)
        }
        primitives.push(
          Path(path, fill, stroke, object.line_width, {
            evenOdd: false,
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
      // Imported text may overflow its frame; report only geometry we could not build.
      if !diagnostic.is_empty() && lines.is_empty() {
        diagnostics.push(object.id + ":" + diagnostic)
        primitives.push(
          Stroke(
            { x: 0, y: 0, width: geometry.width, height: geometry.height, },
            "bb4444",
            1,
          ),
        )
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
        for line in presentation_bold_pens(lines) {
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
          let commands = presentation_line_primitives(
            { ..line, clip: false, },
            fonts,
            frame.width,
            probe,
          )
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
    "regions": document.drawing(images, glyph_raster=FractionalGlyphs),
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
      probe.font_info(),
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
