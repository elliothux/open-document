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
  let width = geometry.width - object.body.left - object.body.right
  for index, paragraph in object.paragraphs {
    let spans : Array[@layout.Span] = []
    for run in paragraph.runs {
      for (style, text) in run.parts {
        spans.push({
          node: run.source.map(item => item.node.id).unwrap_or(0),
          text: text.replace_all(old="\u2028", new="\n"),
          image: None,
          field: "",
          style: { ..style, size: style.size * scale, },
        })
      }
    }
    let spacing : @layout.LineSpacing = match paragraph.spacing {
      Exact(value) => Exact(value * scale)
      AtLeast(value) => AtLeast(value * scale)
      Auto(value) => Auto(value)
    }
    let flow : @layout.Paragraph = {
      id: index,
      container: 0,
      spans,
      nominalSize: spans[0].style.size,
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
    top += paragraph.before.points(measured[0].height)
    for line in measured {
      let advance = match spacing {
        Auto(value) => line.height * value / 240
        _ => line.height
      }
      lines.push({
        ..line,
        start: line.start + offset,
        end: line.end + offset,
        x: line.x + object.body.left,
        y: top,
        height: advance,
        areaX: object.body.left,
        areaWidth: width,
        runs: line.runs.map(run => {
          ..run,
          x: run.x + line.x + object.body.left,
          baseline: run.baseline + top,
        }),
        marker: line.marker.map(run => {
          ..run,
          x: run.x + line.x + object.body.left,
          baseline: run.baseline + top,
        }),
        carets: line.carets.map(caret => {
          ..caret,
          offset: caret.offset + offset,
        }),
      })
      top += advance
    }
    top += paragraph.after.points(measured.last().unwrap().height)
    offset += paragraph.runs
      .iter()
      .fold(init=0, (sum, run) => sum + run.text.length()) +
      1
  }
  (lines, top + object.body.bottom)
}

///|
fn fit_text(
  object : Object,
  geometry : Geometry,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Array[@layout.Line], Double, String) raise @failure.Failure {
  if object.paragraphs.is_empty() {
    return ([], 1, "")
  }
  let object = { ..object, body: object.shape_body(geometry), }
  let mut scale = 1.0
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
    result.0.all(line => {
      line.width <= geometry.width - object.body.left - object.body.right + 0.01
    })
  }
  if object.body.fit == "shrink" && !fits(measured) {
    let mut low = 0.1
    let mut high = 1.0
    for _ in 0..<10 {
      let trial = (low + high) / 2
      let result = measure_text(object, geometry, probe, profile, trial) catch {
        @failure.Failure(code="layout-overflow", ..) =>
          ([], geometry.height + 1)
        error => raise error
      }
      if fits(result) {
        low = trial
      } else {
        high = trial
      }
    }
    scale = low
    measured = measure_text(object, geometry, probe, profile, scale)
  }
  let diagnostic = if measured.1 > geometry.height + 0.01 ||
    measured.0.any(line => {
      line.width > geometry.width - object.body.left - object.body.right + 0.01
    }) {
    "Text exceeds the fixed frame"
  } else {
    ""
  }
  let free = (geometry.height - measured.1).max(0)
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
    }),
    scale,
    diagnostic,
  )
}

///|
fn paint_slide(
  slide : Slide,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  tile_sizes : Map[String, (Int, Int)],
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
      let (commands, lines, warnings, glyphs) = object.paint_table(
        probe, profile,
      )
      primitives.append(commands)
      texts.push({ object: object.id, matrix: geometry.matrix, lines, })
      diagnostics.append(warnings)
      units += glyphs
      guard units <= 262144 else {
        @failure.reject("limit-exceeded", "Slide glyphs exceed budget")
      }
    } else {
      if !object.polyline.is_empty() {
        primitives.push(
          Path(
            object.polyline_path(geometry),
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
        } else if object.gradient is Some((stops, angle, scaled)) &&
          geometry.width > 0 &&
          geometry.height > 0 {
          primitives.push(ClipPath(path, false))
          primitives.append(
            Linear(stops, angle, scaled).paint(geometry.width, geometry.height),
          )
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
      let (lines, _, diagnostic) = fit_text(object, geometry, probe, profile) catch {
        @failure.Failure(code="layout-overflow", message~, ..) =>
          ([], 1.0, message)
        error => raise error
      }
      if !diagnostic.is_empty() {
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
      texts.push({ object: object.id, matrix: geometry.matrix, lines, })
      if !lines.is_empty() {
        primitives.push(
          Clip({ x: 0, y: 0, width: geometry.width, height: geometry.height, }),
        )
        for line in lines {
          // Keep the presentation's frame-level clipping for exact-spaced lines.
          primitives.append(
            { ..line, clip: false, }.positioned(fonts, geometry.width),
          )
          units += [..line.marker, ..line.runs]
            .iter()
            .fold(init=0, (sum, run) => sum + run.glyphs.length())
          guard units <= 262144 else {
            @failure.reject("limit-exceeded", "Slide glyphs exceed budget")
          }
        }
        primitives.push(Restore)
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
  revision : Int,
  all : Bool,
  hidden : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.PositionedDocument raise @failure.Failure {
  self.check_revision(revision)
  self.check_candidate_idle()
  let pages : Array[@layout.PositionedPage] = []
  let mut primitives = 0
  for slide in (if all { self.slides } else { [self.current()] }) {
    if !all || hidden || !slide.hidden {
      let (page, _, diagnostics) = paint_slide(
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
      pages.push(page)
    }
  }
  guard !pages.is_empty() else {
    @failure.reject("unsupported-pdf", "No slides selected for PDF")
  }
  { pages, fonts: probe.font_info(), }
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
