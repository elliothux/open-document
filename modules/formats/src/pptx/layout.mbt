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
      defaultTab: 36,
      tabs: [],
      decimalSymbol: ".",
      expandSoftBreak: true,
      left: paragraph.left,
      right: paragraph.right,
      first: if paragraph.bullet.is_empty() {
        paragraph.first
      } else {
        0
      },
      align: paragraph.align,
      before: 0,
      after: 0,
      line: spacing,
      pageBreakBefore: false,
      readOnlyReason: object.text_reason,
    }
    let measured = probe.paragraph_lines(flow, profile, width, object.body.wrap)
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
  let mut scale = 1.0
  let mut measured = measure_text(object, geometry, probe, profile, scale) catch {
    @failure.Failure(code="layout-overflow", ..) if object.body.fit =>
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
  if object.body.fit && measured.1 > geometry.height {
    let mut low = 0.1
    let mut high = 1.0
    for _ in 0..<10 {
      let trial = (low + high) / 2
      let result = measure_text(object, geometry, probe, profile, trial) catch {
        @failure.Failure(code="layout-overflow", ..) =>
          ([], geometry.height + 1)
        error => raise error
      }
      if result.1 <= geometry.height {
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
) -> (@layout.PositionedPage, Array[TextGeometry], Array[String]) raise @failure.Failure {
  let primitives : Array[@layout.PositionedPrimitive] = [
    Rectangle({
      x: 0,
      y: 0,
      width,
      height,
      color: if slide.background.is_empty() {
        "ffffff"
      } else {
        slide.background
      },
    }),
  ]
  let texts : Array[TextGeometry] = []
  let diagnostics = slide.diagnostics.copy()
  let mut units = 0
  for object in slide.objects {
    guard object.geometry is Some(geometry) else { continue }
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
    } else {
      if object.kind == "image" && object.image is Some(key) {
        let crop = object.crop
        let image_width = geometry.width / (1 - crop[0] - crop[2])
        let image_height = geometry.height / (1 - crop[1] - crop[3])
        primitives.push(
          Clip({ x: 0, y: 0, width: geometry.width, height: geometry.height, }),
        )
        primitives.push(
          Image({
            key,
            x: -crop[0] * image_width,
            y: -crop[1] * image_height,
            width: image_width,
            height: image_height,
          }),
        )
        primitives.push(Restore)
      } else if !object.fill.is_empty() || !object.stroke.is_empty() {
        primitives.push(
          Path(
            shape_path(object.preset, geometry.width, geometry.height),
            object.fill,
            object.stroke,
            object.line_width,
          ),
        )
      }
      let (lines, scale, diagnostic) = fit_text(
        object, geometry, probe, profile,
      ) catch {
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
        for index, paragraph in object.paragraphs {
          if !paragraph.bullet.is_empty() &&
            lines.iter().find_first(line => line.paragraph == index)
            is Some(line) {
            let block = probe.text_block(
              paragraph.bullet,
              {
                ..paragraph.bullet_style,
                size: paragraph.bullet_style.size * scale,
              },
              profile,
              geometry.width.max(1),
              false,
            )
            for text in block.texts {
              primitives.push(
                Text({
                  ..text,
                  runs: text.runs.map(run => {
                    ..run,
                    x: run.x +
                    object.body.left +
                    paragraph.left +
                    paragraph.first,
                    baseline: line.runs
                    .get(0)
                    .map(item => item.baseline)
                    .unwrap_or(line.y + line.height),
                  }),
                }),
              )
            }
          }
        }
        for line in lines {
          primitives.push(
            Text({
              text: line.text,
              runs: line.runs.map(run => {
                color: run.color,
                text: run.text,
                glyphs: run.glyphs,
                x: run.x,
                baseline: run.baseline,
              }),
            }),
          )
          units += line.runs
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
  )
  let document : @layout.PositionedDocument = {
    pages: [page],
    fonts: probe.font_info(),
  }
  let resources : Array[String] = []
  for object in slide.objects {
    if object.image is Some(key) &&
      !resources.contains(images.get(key).identity) {
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
  self.check_idle()
  let pages : Array[@layout.PositionedPage] = []
  let mut primitives = 0
  for slide in self.slides {
    if (all && (hidden || !slide.hidden)) ||
      (!all && slide.tree.part == self.selection.slide) {
      let (page, _, diagnostics) = paint_slide(
        slide,
        self.width,
        self.height,
        probe,
        profile,
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
  for slide in self.slides {
    if (all && (hidden || !slide.hidden)) ||
      (!all && slide.tree.part == self.selection.slide) {
      for object in slide.objects {
        if object.image is Some(key) && !keys.contains(key) {
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
