///|
/// Page-local ink samples in points; each completed stroke is one native drawing.
pub(all) struct InkStroke {
  points : Array[(Double, Double)]
  color : String
  width : Double
  highlighter : Bool
}

///|
priv struct InkGeometry {
  x : Double
  y : Double
  width : Double
  height : Double
  shape : @layout.BasicShape
}

///|
fn Session::ink_page(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  page : Int32,
) -> @layout.PageFrame raise @failure.Failure {
  self.check_revision(revision)
  guard layout.revision == revision && layout.diagnostics.is_empty() else {
    @failure.reject("stale-layout", "Ink requires the current supported layout")
  }
  guard layout.pages.get(page) is Some(frame) else {
    @failure.reject("invalid-operation", "Ink page is outside the document")
  }
  frame
}

///|
fn InkStroke::geometry(
  self : InkStroke,
  page : @layout.PageFrame,
) -> InkGeometry raise @failure.Failure {
  guard self.points.length() > 0 && self.points.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Ink requires 1 to 4096 points")
  }
  guard self.color.length() == 6 &&
    self.color.iter().all(ch => ch.is_ascii_hexdigit()) &&
    self.width >= 0.5 &&
    self.width <= 24 &&
    !self.width.is_nan() &&
    self.points.all(point => {
      !point.0.is_nan() &&
      !point.1.is_nan() &&
      point.0 >= 0 &&
      point.0 <= page.width &&
      point.1 >= 0 &&
      point.1 <= page.height
    }) else {
    @failure.reject(
      "invalid-operation", "Invalid ink samples or stroke settings",
    )
  }
  let points = if self.points.all(point => point == self.points[0]) {
    let point = self.points[0]
    let direction = if point.0 + 0.01 <= page.width { 0.01 } else { -0.01 }
    [point, (point.0 + direction, point.1)]
  } else {
    self.points.copy()
  }
  let mut x = points[0].0
  let mut y = points[0].1
  let mut right = x
  let mut bottom = y
  for point in points {
    x = x.min(point.0)
    y = y.min(point.1)
    right = right.max(point.0)
    bottom = bottom.max(point.1)
  }
  let width = (right - x).max(0.1)
  let height = (bottom - y).max(0.1)
  {
    x,
    y,
    width,
    height,
    shape: {
      preset: "polyline",
      fill: "",
      stroke: self.color.to_upper(),
      lineWidth: self.width,
      strokeAlpha: if self.highlighter {
        0.45
      } else {
        1
      },
      points: points.map(point => {
        ((point.0 - x) / width, (point.1 - y) / height)
      }),
    },
  }
}

///|
/// Builds a transparent R0 preview without changing source, selection or history.
pub fn Session::preview_ink(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  page : Int32,
  stroke : InkStroke,
) -> Json raise @failure.Failure {
  let frame = self.ink_page(revision, layout, page)
  let geometry = stroke.geometry(frame)
  let path = geometry.shape.points.mapi((index, point) => {
    let x = geometry.x + point.0 * geometry.width
    let y = geometry.y + point.1 * geometry.height
    if index == 0 {
      @layout.Move(x, y)
    } else {
      @layout.Line(x, y)
    }
  })
  let region : @layout.DrawingRegion = {
    width: frame.width,
    height: frame.height,
    commands: [
      @layout.Style({
        ..@layout.DrawStyle::default(),
        strokeAlpha: geometry.shape.strokeAlpha,
        cap: 1,
        join: 1,
      }),
      @layout.Path(path, "", geometry.shape.stroke, geometry.shape.lineWidth),
    ],
  }
  { "regions": [region], "outlines": [], "images": [] }
}

///|
/// Anchors a completed stroke to the nearest body paragraph as one undoable edit.
pub fn Session::insert_ink(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  page : Int32,
  stroke : InkStroke,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  let frame = self.ink_page(revision, layout, page)
  let geometry = stroke.geometry(frame)
  self.check_document_protection()
  let tree = WordTree::new(self.document())
  let mut chosen : @layout.Line? = None
  let mut distance = 1.0e30
  for line in frame.lines {
    let parent = tree.nodes
      .get(line.paragraph)
      .map(node => node.parent)
      .unwrap_or(-1)
    if parent < 0 ||
      tree.nodes[parent].uri != word_uri ||
      tree.nodes[parent].name != "body" ||
      !line.readOnlyReason.is_empty() ||
      line.repeated {
      continue
    }
    let dx = (line.x - stroke.points[0].0).max(0) +
      (stroke.points[0].0 - line.x - line.width).max(0)
    let dy = (line.y - stroke.points[0].1).max(0) +
      (stroke.points[0].1 - line.y - line.height).max(0)
    let next = dx * dx + dy * dy
    if next < distance {
      chosen = Some(line)
      distance = next
    }
  }
  guard chosen is Some(line) else {
    @failure.reject(
      "protected-content", "Ink requires an editable body paragraph on this page",
    )
  }
  let origin_y = frame.lines
    .iter()
    .find_first(prior => {
      prior.paragraph == line.paragraph && prior.areaX == line.areaX
    })
    .map(prior => prior.y)
    .unwrap_or(line.y)
  let mut order = 0L
  for paragraph in self.flow().paragraphs {
    for span in paragraph.spans {
      if span.drawing.bind(drawing => drawing.anchor) is Some(anchor) {
        order = order.max(anchor.order)
      }
    }
  }
  guard order < 4294967295L else {
    @failure.reject("limit-exceeded", "Drawing stacking order is exhausted")
  }
  let anchor : @layout.DrawingAnchor = {
    horizontal: @layout.Offset("column", geometry.x - line.areaX),
    vertical: @layout.Offset("paragraph", geometry.y - origin_y),
    behind: false,
    order: order + 1,
    wrapping: "none",
    wrapSide: "bothSides",
    distance: { top: 0, right: 0, bottom: 0, left: 0, },
  }
  anchor.validate()
  let markup = self.ink_markup(geometry, anchor)
  let position : Position = {
    paragraph: line.paragraph,
    offset: line.start,
    affinity: "before",
    bidiLevel: None,
    frameStart: None,
  }
  let view = {
    ..self,
    selection: Some({ anchor: position, focus: position, }),
  }
  let prepared = view.prepare_drawing_insertion(markup)
  let candidate = @layout.paginate(
    probe,
    self.flow_from(prepared.document),
    profile,
    images,
  )
  guard candidate.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Ink requires supported document layout",
    )
  }
  self.commit_edit(
    {
      ..prepared.edit,
      before: self.selection,
      after: Some({
        anchor: position,
        focus: { ..position, offset: position.offset + 1, affinity: "after", },
      }),
    },
    prepared.document,
  )
  self.edit_result(prepared.edit.paragraphs)
}

///|
/// Erases the topmost ink stroke under a page-local point; other drawings remain.
pub fn Session::erase_ink(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  page : Int32,
  x : Double,
  y : Double,
) -> Json raise @failure.Failure {
  let frame = self.ink_page(revision, layout, page)
  guard x >= 0 && x <= frame.width && y >= 0 && y <= frame.height else {
    @failure.reject("invalid-operation", "Ink eraser lies outside the page")
  }
  let hit = layout.hit_test(page, x, y)
  guard hit.drawingStart is Some(start) else { return self.edit_result([]) }
  let position : Position = {
    paragraph: hit.paragraph,
    offset: start,
    affinity: "before",
    bidiLevel: None,
    frameStart: None,
  }
  let view = {
    ..self,
    selection: Some({
      anchor: position,
      focus: { ..position, offset: start + 1, },
    }),
  }
  let tree = WordTree::new(self.document())
  guard view.selected_drawing(tree) is Some(id) &&
    self.drawing_frame(tree, id).content
    is @layout.Shape({ preset: "polyline", .. }) else {
    return self.edit_result([])
  }
  self.delete_shape(revision, id)
}

///|
fn Session::ink_markup(
  self : Session,
  geometry : InkGeometry,
  anchor : @layout.DrawingAnchor,
) -> String raise @failure.Failure {
  let identity = self.next_drawing_identity()
  let cx = (geometry.width * 12700).round().to_int64()
  let cy = (geometry.height * 12700).round().to_int64()
  let path = StringBuilder()
  for index, point in geometry.shape.points {
    let command = if index == 0 { "moveTo" } else { "lnTo" }
    path.write_string(
      "<a:\{command}><a:pt x=\"\{(point.0 * cx.to_double()).round().to_int64()}\" y=\"\{(point.1 * cy.to_double()).round().to_int64()}\"/></a:\{command}>",
    )
  }
  let line = shape_fill_markup(
    geometry.shape.stroke,
    alpha=geometry.shape.strokeAlpha,
  )
  let weight = (geometry.shape.lineWidth * 12700).round().to_int64()
  let position = drawing_axis_markup(anchor.horizontal, "positionH") +
    drawing_axis_markup(anchor.vertical, "positionV")
  let markup = "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:wps=\"\{word_shape_uri}\"><wp:anchor simplePos=\"0\" relativeHeight=\"\{anchor.order}\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/>\{position}<wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:wrapNone/><wp:docPr id=\"\{identity}\" name=\"Ink \{identity}\"/><a:graphic><a:graphicData uri=\"\{word_shape_uri}\"><wps:wsp><wps:cNvSpPr/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm><a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"l\" t=\"t\" r=\"r\" b=\"b\"/><a:pathLst><a:path w=\"\{cx}\" h=\"\{cy}\" fill=\"none\">\{path.to_string()}</a:path></a:pathLst></a:custGeom><a:noFill/><a:ln w=\"\{weight}\" cap=\"rnd\">\{line}<a:round/></a:ln></wps:spPr><wps:bodyPr/></wps:wsp></a:graphicData></a:graphic></wp:anchor></od:drawing>"
  guard markup.length() <=
    self.opc.budget.entry_bytes.min(history_byte_limit / 2) else {
    @failure.reject("limit-exceeded", "Ink source exceeds the drawing budget")
  }
  markup
}
