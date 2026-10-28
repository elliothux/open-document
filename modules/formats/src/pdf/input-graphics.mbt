///|
priv struct GraphicsState {
  matrix : @layout.Matrix
  fill : String
  stroke : String
  width : Double
  style : @layout.DrawStyle
  text : @pdflite.PdfContentTextState
  font : SourceFont?
  clips : Int32
  fillSpace : String
  strokeSpace : String
}

///|
priv struct MarkedText {
  replacement : String?
  span : Int32
  chunk : Int32
  offset : Int32
}

///|
priv struct ContentContext {
  sources : Array[PdfSourceObject]
  mut collectSource : Bool
  session : PdfSession
  page : SourcePage
  probe : @layout.TextProbe
  supplied : @layout.TextProbe
  profile : Map[String, String]
  images : @layout.Images
  commands : Array[@layout.DrawCommand]
  diagnostics : Array[String]
  spans : Array[TextSpan]
  chunks : Array[String]
  mut units : Int32
  mut textComplete : Bool
  mut displayComplete : Bool
  fonts : Map[String, SourceFont]
  imageKeys : Array[String]
  jpeg : Map[String, JpegImage]
  forms : Map[String, Bool]
  marked : Array[MarkedText]
  mut nesting : Int32
}

///|
fn matrix(value : @geometry.TransformMatrix) -> @layout.Matrix {
  { a: value.a, b: value.b, c: value.c, d: value.d, e: value.e, f: value.f, }
}

///|
fn geometry_matrix(value : @layout.Matrix) -> @geometry.TransformMatrix {
  { a: value.a, b: value.b, c: value.c, d: value.d, e: value.e, f: value.f, }
}

///|
fn ContentContext::scope(
  self : ContentContext,
  command : @layout.DrawCommand,
) -> Unit raise @failure.Failure {
  if command is Transform(matrix) {
    ignore(matrix.inverse())
  }
  if command is ClipPath(path, _) {
    ignore(path_in(path, @layout.Matrix::identity()))
  }
  guard self.nesting < 32 else {
    @failure.reject("limit-exceeded", "PDF drawing stack exceeds budget")
  }
  self.commands.push(command)
  self.nesting += 1
}

///|
fn ContentContext::restore(self : ContentContext) -> Unit {
  self.commands.push(@layout.Restore)
  self.nesting -= 1
}

///|
fn ContentContext::append(
  self : ContentContext,
  text : String,
) -> Unit raise @failure.Failure {
  guard text.length() <= 262144 - self.units else {
    @failure.reject("limit-exceeded", "PDF page text exceeds budget")
  }
  self.chunks.push(text)
  self.units += text.length()
}

///|
fn path_in(
  path : Array[@layout.PathSegment],
  transform : @layout.Matrix,
) -> Array[@layout.PathSegment] raise @failure.Failure {
  path.map(segment => {
    match segment {
      Move(x, y) => {
        let (x, y) = checked_point(transform, x, y)
        @layout.Move(x, y)
      }
      Line(x, y) => {
        let (x, y) = checked_point(transform, x, y)
        @layout.Line(x, y)
      }
      Cubic(x1, y1, x2, y2, x, y) => {
        let (x1, y1) = checked_point(transform, x1, y1)
        let (x2, y2) = checked_point(transform, x2, y2)
        let (x, y) = checked_point(transform, x, y)
        @layout.Cubic(x1, y1, x2, y2, x, y)
      }
      Close => @layout.Close
    }
  })
}

///|
fn checked_point(
  matrix : @layout.Matrix,
  x : Double,
  y : Double,
) -> (Double, Double) raise @failure.Failure {
  let point = matrix.point(x, y)
  guard [x, y, point.0, point.1].all(value => {
    !value.is_nan() && !value.is_inf() && value.abs() <= 1000000000
  }) else {
    @failure.reject("limit-exceeded", "PDF path coordinates exceed budget")
  }
  point
}

///|
fn rgb(values : Array[Double]) -> String raise @failure.Failure {
  let values = if values.length() == 1 {
    [values[0], values[0], values[0]]
  } else {
    values
  }
  guard values.length() == 3 else {
    @failure.reject("unsupported-pdf", "Unsupported PDF color space")
  }
  let out = StringBuilder()
  for value in values {
    guard !value.is_nan() && !value.is_inf() else {
      @failure.reject("invalid-pdf", "Invalid PDF color")
    }
    out.write_string(
      (value.max(0).min(1) * 255)
      .round()
      .to_int()
      .to_string(radix=16)
      .pad_start(2, '0'),
    )
  }
  out.to_string()
}

///|
fn ext_state(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @pdfcore.PdfName,
  state : GraphicsState,
) -> GraphicsState raise @failure.Failure {
  let object = get(
    document,
    get(document, resources, "ExtGState"),
    @utf8.decode_lossy(name.bytes())[1:].to_owned(),
  )
  guard object is PdfDictionary(entries) else {
    @failure.reject("invalid-pdf", "Missing ExtGState resource")
  }
  let mut style = state.style
  let mut width = state.width
  for (key, value) in entries {
    let value = resolve(document, value)
    match @utf8.decode_lossy(key.bytes()) {
      "/Type" => ()
      "/ca" | "/CA" as key => {
        let alpha = number(value)
        guard alpha >= 0 && alpha <= 1 else {
          @failure.reject("invalid-pdf", "Invalid PDF transparency")
        }
        style = if key == "/ca" {
          { ..style, fillAlpha: alpha, }
        } else {
          { ..style, strokeAlpha: alpha, }
        }
      }
      "/BM" => {
        let value = match value {
          PdfArray([single]) => single
          _ => value
        }
        guard is_name(value, "Normal") ||
          is_name(value, "Compatible") ||
          is_name(value, "Multiply") else {
          @failure.reject("unsupported-pdf", "Unsupported PDF blend mode")
        }
        style = { ..style, multiply: is_name(value, "Multiply"), }
      }
      "/LW" => width = number(value)
      "/LC" => style = { ..style, cap: integer(value), }
      "/LJ" => style = { ..style, join: integer(value), }
      "/ML" => style = { ..style, miter: number(value), }
      "/D" => {
        guard value is PdfArray([PdfArray(items), offset]) else {
          @failure.reject("invalid-pdf", "Invalid PDF dash array")
        }
        style = {
          ..style,
          dash: items.map(number),
          dashOffset: number(offset),
        }
      }
      "/SMask" if is_name(value, "None") => ()
      "/AIS" | "/OP" | "/op" if value == @syntax.PdfBoolean(false) => ()
      "/OPM" if value == @syntax.PdfInteger(0) => ()
      "/TK" if value == @syntax.PdfBoolean(true) => ()
      _ =>
        @failure.reject(
          "unsupported-pdf", "Unsupported PDF graphics state property",
        )
    }
  }
  { ..state, style, width, }
}

///|
fn check_style(
  style : @layout.DrawStyle,
  width : Double,
) -> Unit raise @failure.Failure {
  guard !style.dashOffset.is_nan() &&
    !style.dashOffset.is_inf() &&
    style.dashOffset.abs() <= 1000000000 &&
    width >= 0 &&
    width <= 14400 &&
    [0, 1, 2].contains(style.cap) &&
    [0, 1, 2].contains(style.join) &&
    style.miter >= 1 &&
    style.miter <= 1000000 &&
    style.dash.length() <= 256 &&
    style.dash.all(value => {
      value >= 0 && value <= 1000000000 && !value.is_nan() && !value.is_inf()
    }) &&
    (style.dash.is_empty() || style.dash.any(value => value > 0)) else {
    @failure.reject("invalid-pdf", "Invalid PDF stroke style")
  }
}
