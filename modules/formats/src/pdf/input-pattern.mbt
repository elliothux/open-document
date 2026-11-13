///|
priv struct TilingPattern {
  id : Int32
  resources : @syntax.PdfObject
  bytes : Bytes
  bbox : (Double, Double, Double, Double)
  matrix : @layout.Matrix
  xstep : Double
  ystep : Double
  uncolored : Bool
  raster : Bool
}

///|
fn ContentContext::pattern_color(
  self : ContentContext,
  resources : @syntax.PdfObject,
  name : @pdfcore.PdfName,
  space : InputColorSpace,
  values : Array[Double],
) -> (TilingPattern, String) raise {
  guard space is PatternColor(base) else {
    @failure.reject(
      "invalid-pdf", "Named pattern requires a pattern color space",
    )
  }
  let document = self.session.document
  let reference = raw(
    get(document, resources, "Pattern"),
    @utf8.decode_lossy(name.bytes())[1:].to_owned(),
  )
  let object = resolve(document, reference)
  guard reference is PdfIndirect(id) &&
    object is PdfStreamObject(_) &&
    [@syntax.PdfNull, tag("Pattern")].contains(get(document, object, "Type")) &&
    get(document, object, "PatternType") == @syntax.PdfInteger(1) else {
    @failure.reject("unsupported-pdf", "PDF pattern requires a tiling stream")
  }
  let paint = integer(get(document, object, "PaintType"))
  let tiling = integer(get(document, object, "TilingType"))
  guard [1, 2].contains(paint) &&
    [1, 2, 3].contains(tiling) &&
    (paint == 2) == (base is Some(_)) else {
    @failure.reject(
      "invalid-pdf", "Invalid PDF pattern painting type or base color",
    )
  }
  let color = match base {
    Some(space) => space.color(values)
    None => {
      guard values.is_empty() else {
        @failure.reject(
          "invalid-pdf", "Colored pattern cannot take color components",
        )
      }
      ""
    }
  }
  let xstep = number(get(document, object, "XStep")).abs()
  let ystep = number(get(document, object, "YStep")).abs()
  guard xstep > 0 && ystep > 0 else {
    @failure.reject("invalid-pdf", "PDF pattern steps must be nonzero")
  }
  let resources = get(document, object, "Resources")
  guard resources is PdfDictionary(_) else {
    @failure.reject("invalid-pdf", "PDF pattern requires resource dictionary")
  }
  let matrix = pdf_object_matrix(get(document, object, "Matrix"))
  ignore(matrix.inverse())
  (
    {
      id,
      resources,
      bytes: stream_bytes(document, reference),
      bbox: rectangle(get(document, object, "BBox")),
      matrix,
      xstep,
      ystep,
      uncolored: paint == 2,
      raster: tiling != 2,
    },
    color,
  )
}

///|
fn ContentContext::tiling_pattern(
  self : ContentContext,
  path : Array[@layout.PathSegment],
  state : GraphicsState,
  base : @layout.Matrix,
  even_odd : Bool,
  depth : Int32,
) -> Unit raise {
  guard state.fillPattern is Some(pattern) else { return }
  guard self.extraction is None else {
    @failure.reject(
      "protected-content", "PDF tiling patterns require source preservation",
    )
  }
  let key = "pdf-image-\{pattern.id}"
  guard !self.forms.contains(key) else {
    @failure.reject("invalid-pdf", "Cyclic PDF tiling pattern")
  }
  self.forms[key] = true
  defer self.forms.remove(key)
  // Pattern space follows the page/Form base matrix, independently of later cm operators.
  let matrix = base.then(pattern.matrix)
  let inverse = matrix.inverse()
  let points : Array[(Double, Double)] = []
  for segment in path {
    @pdfcore.sdk_check(1)
    match segment {
      Move(x, y) | Line(x, y) => points.push((x, y))
      Cubic(a, b, c, d, x, y) => points.append([(a, b), (c, d), (x, y)])
      Close => ()
    }
  }
  if points.is_empty() {
    return
  }
  let left = points
    .fold(init=self.page.width, (value, p) => value.min(p.0))
    .max(0)
  let right = points
    .fold(init=0.0, (value, p) => value.max(p.0))
    .min(self.page.width)
  let top = points
    .fold(init=self.page.height, (value, p) => value.min(p.1))
    .max(0)
  let bottom = points
    .fold(init=0.0, (value, p) => value.max(p.1))
    .min(self.page.height)
  if left >= right || top >= bottom {
    return
  }
  let corners = [(left, top), (right, top), (left, bottom), (right, bottom)].map(p => {
      checked_point(inverse, p.0, p.1)
    },
  )
  let (x0, y0, x1, y1) = pattern.bbox
  let low_x = ((corners.fold(init=1000000000.0, (v, p) => v.min(p.0)) - x1) /
  pattern.xstep).ceil()
  let high_x = ((corners.fold(init=-1000000000.0, (v, p) => v.max(p.0)) - x0) /
  pattern.xstep).floor()
  let low_y = ((corners.fold(init=1000000000.0, (v, p) => v.min(p.1)) - y1) /
  pattern.ystep).ceil()
  let high_y = ((corners.fold(init=-1000000000.0, (v, p) => v.max(p.1)) - y0) /
  pattern.ystep).floor()
  guard [low_x, high_x, low_y, high_y].all(v => {
      !v.is_inf() && v.abs() <= 1000000000.0
    }) &&
    (high_x - low_x + 1).max(0) * (high_y - low_y + 1).max(0) <= 4096 else {
    @failure.reject("limit-exceeded", "PDF pattern tiles exceed budget")
  }
  if low_x > high_x || low_y > high_y {
    return
  }
  self.scope(@layout.ClipPath(path.copy(), even_odd))
  defer self.restore()
  let width = x1 - x0
  let height = y1 - y0
  let columns = (high_x - low_x + 1).to_int()
  let rows = (high_y - low_y + 1).to_int()
  let first_matrix = matrix.then({
    a: 1,
    b: 0,
    c: 0,
    d: 1,
    e: low_x * pattern.xstep,
    f: low_y * pattern.ystep,
  })
  let first = if pattern.raster &&
    pattern.xstep == width &&
    pattern.ystep == height &&
    state.softMask is None &&
    state.style.blend == Normal &&
    state.style.fillAlpha == 1 &&
    state.style.strokeAlpha == 1 {
    Some(self.pattern_cell(pattern, state, first_matrix, depth))
  } else {
    None
  }
  if first is Some(commands) && pattern_repeatable(commands) {
    let origin = first_matrix.then({ a: 1, b: 0, c: 0, d: 1, e: x0, f: y0, })
    let cell_commands : Array[@layout.DrawCommand] = [
      @layout.Transform(origin.inverse()),
      ..commands,
      @layout.Restore,
    ]
    input_layer_budget(cell_commands, 1)
    self.commands.push(@layout.Style(state.style))
    self.commands.push(
      @layout.Tile(
        width,
        height,
        columns,
        rows,
        origin,
        pattern.matrix.a.abs().max(pattern.matrix.c.abs()),
        pattern.matrix.b.abs().max(pattern.matrix.d.abs()),
        cell_commands,
      ),
    )
    return
  }
  for row in low_y.to_int()..<=high_y.to_int() {
    for column in low_x.to_int()..<=high_x.to_int() {
      @pdfcore.sdk_check(1)
      let commands = if row == low_y.to_int() &&
        column == low_x.to_int() &&
        first is Some(commands) {
        commands
      } else {
        self.pattern_cell(
          pattern,
          state,
          matrix.then({
            a: 1,
            b: 0,
            c: 0,
            d: 1,
            e: column.to_double() * pattern.xstep,
            f: row.to_double() * pattern.ystep,
          }),
          depth,
        )
      }
      self.commands.append(commands)
      guard self.commands.length() <= 1048576 else {
        @failure.reject("limit-exceeded", "PDF pattern drawing exceeds budget")
      }
    }
  }
}

///|
fn pattern_repeatable(commands : Array[@layout.DrawCommand]) -> Bool {
  commands.all(command => {
    match command {
      Style(style) =>
        style.fillAlpha == 1 && style.strokeAlpha == 1 && style.blend == Normal
      Mask(_, _, ..) | Layer(_, _) | Tile(_, _, _, _, _, _, _, _) => false
      _ => true
    }
  })
}

///|
fn ContentContext::pattern_cell(
  self : ContentContext,
  pattern : TilingPattern,
  state : GraphicsState,
  transform : @layout.Matrix,
  depth : Int32,
) -> Array[@layout.DrawCommand] raise {
  let (x0, y0, x1, y1) = pattern.bbox
  let space = match state.fillSpace {
    PatternColor(Some(space)) => space
    _ => GrayColor
  }
  let color = if pattern.uncolored { state.fill } else { "000000" }
  let child : ContentContext = {
    ..self,
    commands: [],
    extraction: None,
    sources: [],
    collectSource: false,
    spans: [],
    chunks: [],
    units: 0,
    textComplete: true,
    displayComplete: true,
    marked: [],
  }
  child.scope(
    @layout.ClipPath(
      path_in(
        [
          @layout.Move(x0, y0),
          @layout.Line(x1, y0),
          @layout.Line(x1, y1),
          @layout.Line(x0, y1),
          @layout.Close,
        ],
        transform,
      ),
      false,
    ),
  )
  interpret(
    child,
    pattern.bytes,
    pattern.resources,
    "pattern:\{pattern.id}",
    {
      ..state,
      matrix: transform,
      clips: 0,
      fill: color,
      stroke: color,
      fillSpace: space,
      strokeSpace: space,
      fillPattern: None,
      width: 0,
      style: { ..state.style, dash: [], dashOffset: 0, },
    },
    depth + 1,
    uncolored=pattern.uncolored,
  )
  child.restore()
  guard child.displayComplete else {
    @failure.reject("unsupported-pdf", "PDF pattern content is incomplete")
  }
  child.commands
}
