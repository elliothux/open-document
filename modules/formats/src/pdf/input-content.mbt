///|
priv struct GraphicsState {
  matrix : @layout.Matrix
  fill : String
  stroke : String
  width : Double
  style : @layout.DrawStyle
  text : @pdflite.PdfContentTextState
  font : SourceFont?
  clips : Int
  fillSpace : String
  strokeSpace : String
}

///|
priv struct MarkedText {
  replacement : String?
  span : Int
  chunk : Int
  offset : Int
}

///|
priv struct ContentContext {
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
  mut units : Int
  mut textComplete : Bool
  mut displayComplete : Bool
  fonts : Map[String, SourceFont]
  imageKeys : Array[String]
  jpeg : Map[String, JpegImage]
  forms : Map[String, Bool]
  marked : Array[MarkedText]
  mut nesting : Int
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

///|
fn interpret(
  context : ContentContext,
  bytes : Bytes,
  resources : @syntax.PdfObject,
  identity : String,
  initial : GraphicsState,
  depth : Int,
) -> Unit raise {
  guard depth < 32 else {
    @failure.reject("limit-exceeded", "PDF Form depth exceeds budget")
  }
  let document = context.session.document
  let ops = @pdflite.pdf_parse_content_ops_from_view(bytes)
  let stack : Array[GraphicsState] = []
  let mut state = initial
  let path : Array[@layout.PathSegment] = []
  let mut point = (0.0, 0.0)
  let mut start = point
  let mut clip : Bool? = None
  let mut compatibility = 0
  let marked_start = context.marked.length()
  for op_index, op in ops {
    @pdfcore.sdk_check(1)
    guard context.commands.length() + context.spans.length() + path.length() <=
      1048576 else {
      @failure.reject("limit-exceeded", "PDF drawing payload exceeds budget")
    }
    match op {
      Op_q => {
        stack.push(state)
        context.scope(@layout.Transform(@layout.Matrix::identity()))
      }
      Op_Q => {
        guard stack.pop() is Some(saved) else {
          @failure.reject("invalid-pdf", "PDF graphics stack underflow")
        }
        for _ in 0..<(state.clips - saved.clips + 1) {
          context.restore()
        }
        state = saved
      }
      Op_cm(value) => {
        state = { ..state, matrix: state.matrix.then(matrix(value)), }
        ignore(state.matrix.inverse())
      }
      Op_m(x, y) => {
        point = state.matrix.point(x, y)
        start = point
        path.push(@layout.Move(point.0, point.1))
      }
      Op_l(x, y) => {
        point = state.matrix.point(x, y)
        path.push(@layout.Line(point.0, point.1))
      }
      Op_c(x1, y1, x2, y2, x, y) => {
        let p1 = state.matrix.point(x1, y1)
        let p2 = state.matrix.point(x2, y2)
        point = state.matrix.point(x, y)
        path.push(@layout.Cubic(p1.0, p1.1, p2.0, p2.1, point.0, point.1))
      }
      Op_v(x2, y2, x, y) => {
        let p2 = state.matrix.point(x2, y2)
        let p = state.matrix.point(x, y)
        path.push(@layout.Cubic(point.0, point.1, p2.0, p2.1, p.0, p.1))
        point = p
      }
      Op_y(x1, y1, x, y) => {
        let p1 = state.matrix.point(x1, y1)
        point = state.matrix.point(x, y)
        path.push(@layout.Cubic(p1.0, p1.1, point.0, point.1, point.0, point.1))
      }
      Op_h => {
        path.push(@layout.Close)
        point = start
      }
      Op_re(x, y, w, h) => {
        let points = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)].map(p => {
          state.matrix.point(p.0, p.1)
        })
        start = points[0]
        point = start
        path.push(@layout.Move(start.0, start.1))
        for p in points[1:] {
          path.push(@layout.Line(p.0, p.1))
        }
        path.push(@layout.Close)
      }
      Op_W => clip = Some(false)
      Op_Wstar => clip = Some(true)
      Op_n
      | Op_S
      | Op_s
      | Op_f
      | Op_F
      | Op_fstar
      | Op_B
      | Op_Bstar
      | Op_b
      | Op_bstar => {
        if op is (Op_s | Op_b | Op_bstar) {
          path.push(@layout.Close)
        }
        if !path.is_empty() && op != @content.Op_n {
          check_style(state.style, state.width)
          context.commands.push(
            @layout.Style({
              ..state.style,
              evenOdd: op is (Op_fstar | Op_Bstar | Op_bstar),
            }),
          )
          context.scope(@layout.Transform(state.matrix))
          context.commands.push(
            @layout.Path(
              path_in(path, state.matrix.inverse()),
              if op is (Op_S | Op_s) {
                ""
              } else {
                state.fill
              },
              if op is (Op_f | Op_F | Op_fstar) {
                ""
              } else {
                state.stroke
              },
              state.width,
            ),
          )
          context.restore()
        }
        if clip is Some(even_odd) {
          context.scope(@layout.ClipPath(path.copy(), even_odd))
          state = { ..state, clips: state.clips + 1, }
        }
        clip = None
        path.clear()
      }
      Op_w(width) => state = { ..state, width, }
      Op_J(cap) => state = { ..state, style: { ..state.style, cap, }, }
      Op_j(join) => state = { ..state, style: { ..state.style, join, }, }
      Op_M(miter) => state = { ..state, style: { ..state.style, miter, }, }
      Op_d(dash, offset) =>
        state = {
          ..state,
          style: { ..state.style, dash, dashOffset: offset, },
        }
      Op_g(v) => state = { ..state, fill: rgb([v]), fillSpace: "DeviceGray", }
      Op_G(v) =>
        state = { ..state, stroke: rgb([v]), strokeSpace: "DeviceGray", }
      Op_rg(r, g, b) =>
        state = { ..state, fill: rgb([r, g, b]), fillSpace: "DeviceRGB", }
      Op_RG(r, g, b) =>
        state = { ..state, stroke: rgb([r, g, b]), strokeSpace: "DeviceRGB", }
      Op_cs(name) => {
        let space = @utf8.decode_lossy(name.bytes())[1:].to_owned()
        guard ["DeviceGray", "DeviceRGB"].contains(space) else {
          @failure.reject("unsupported-pdf", "Unsupported PDF fill color space")
        }
        state = { ..state, fillSpace: space, fill: "000000", }
      }
      Op_CS(name) => {
        let space = @utf8.decode_lossy(name.bytes())[1:].to_owned()
        guard ["DeviceGray", "DeviceRGB"].contains(space) else {
          @failure.reject(
            "unsupported-pdf", "Unsupported PDF stroke color space",
          )
        }
        state = { ..state, strokeSpace: space, stroke: "000000", }
      }
      Op_sc(values) | Op_scn(values) => {
        guard values.length() ==
          (if state.fillSpace == "DeviceGray" { 1 } else { 3 }) else {
          @failure.reject("invalid-pdf", "Invalid PDF fill color")
        }
        state = { ..state, fill: rgb(values), }
      }
      Op_SC(values) | Op_SCN(values) => {
        guard values.length() ==
          (if state.strokeSpace == "DeviceGray" { 1 } else { 3 }) else {
          @failure.reject("invalid-pdf", "Invalid PDF stroke color")
        }
        state = { ..state, stroke: rgb(values), }
      }
      Op_gs(name) => state = ext_state(document, resources, name, state)
      Op_Tf(name, _) => {
        let fonts = get(document, resources, "Font")
        let value = raw(fonts, @utf8.decode_lossy(name.bytes())[1:].to_owned())
        let key = match value {
          PdfIndirect(id) => "\{id}"
          _ => identity + @utf8.decode_lossy(name.bytes())
        }
        let font = match context.fonts.get(key) {
          Some(font) => font
          None => {
            let font = font_resource(
              document,
              resources,
              name,
              context.probe,
              context.supplied,
              context.profile,
              context.diagnostics,
            )
            context.fonts[key] = font
            font
          }
        }
        state = {
          ..state,
          font: Some(font),
          text: state.text.content_apply_text_state_op(op),
        }
      }
      Op_Tj(_) | Op_TJ(_) | Op_quote(_) | Op_double_quote(_, _, _) =>
        state = show_text(context, state, op, "\{identity}:\{op_index}")
      Op_BT
      | Op_ET
      | Op_Tc(_)
      | Op_Tw(_)
      | Op_Tz(_)
      | Op_TL(_)
      | Op_Tr(_)
      | Op_Ts(_)
      | Op_Td(_, _)
      | Op_TD(_, _)
      | Op_Tm(_)
      | Op_Tstar =>
        state = { ..state, text: state.text.content_apply_text_state_op(op), }
      Op_Do(name) => {
        let xobjects = get(document, resources, "XObject")
        let reference = raw(
          xobjects,
          @utf8.decode_lossy(name.bytes())[1:].to_owned(),
        )
        let key = match reference {
          PdfIndirect(id) => "pdf-image-\{id}"
          _ => identity + @utf8.decode_lossy(name.bytes())
        }
        let object = resolve(document, reference)
        if is_name(raw(object, "Subtype"), "Image") {
          let available = try {
            add_image(context, object, key)
            true
          } catch {
            @failure.Failure(
              code="unsupported-pdf"
              | "invalid-pdf"
              | "invalid-image",
              message~,
              ..
            ) => {
              context.displayComplete = false
              context.diagnostics.push(message)
              false
            }
            error => raise error
          }
          if !available {
            continue
          }
          guard raw(object, "Interpolate") == @syntax.PdfNull ||
            raw(object, "Interpolate") is PdfBoolean(_) else {
            @failure.reject(
              "invalid-pdf", "Invalid PDF image interpolation flag",
            )
          }
          context.commands.push(
            @layout.Style({
              ..state.style,
              imageSmoothing: raw(object, "Interpolate") ==
              @syntax.PdfBoolean(true),
            }),
          )
          context.scope(
            @layout.Transform(
              state.matrix.then({ a: 1, b: 0, c: 0, d: -1, e: 0, f: 1, }),
            ),
          )
          context.commands.push(
            @layout.Image({ key, x: 0, y: 0, width: 1, height: 1, }),
          )
          context.restore()
        } else {
          guard is_name(raw(object, "Subtype"), "Form") &&
            !context.forms.contains(key) &&
            raw(object, "OC") == @syntax.PdfNull &&
            raw(object, "Group") == @syntax.PdfNull else {
            @failure.reject(
              "unsupported-pdf", "Unsupported or cyclic PDF XObject",
            )
          }
          let form_matrix = pdf_object_matrix(get(document, object, "Matrix"))
          let form_state = {
            ..state,
            matrix: state.matrix.then(form_matrix),
            clips: 0,
          }
          let (x, y, r, t) = rectangle(get(document, object, "BBox"))
          let bbox : Array[@layout.PathSegment] = [
            @layout.Move(x, y),
            @layout.Line(r, y),
            @layout.Line(r, t),
            @layout.Line(x, t),
            @layout.Close,
          ]
          context.scope(
            @layout.ClipPath(path_in(bbox, form_state.matrix), false),
          )
          context.forms[key] = true
          let own_resources = get(document, object, "Resources")
          interpret(
            context,
            stream_bytes(document, object),
            if own_resources == @syntax.PdfNull {
              resources
            } else {
              own_resources
            },
            key,
            form_state,
            depth + 1,
          )
          context.forms.remove(key)
          context.restore()
        }
      }
      Op_BMC(tag) => {
        guard tag != pdf_name("OC") else {
          @failure.reject(
            "unsupported-pdf", "Optional PDF content is unsupported",
          )
        }
        context.marked.push({
          replacement: None,
          span: context.spans.length(),
          chunk: context.chunks.length(),
          offset: context.units,
        })
      }
      Op_BDC(tag, properties) => {
        guard tag != pdf_name("OC") else {
          @failure.reject(
            "unsupported-pdf", "Optional PDF content is unsupported",
          )
        }
        let properties = if properties is PdfNameObject(name) {
          get(
            document,
            get(document, resources, "Properties"),
            @utf8.decode_lossy(name.bytes())[1:].to_owned(),
          )
        } else {
          resolve(document, properties)
        }
        guard raw(properties, "OC") == @syntax.PdfNull else {
          @failure.reject(
            "unsupported-pdf", "Optional PDF content is unsupported",
          )
        }
        let actual = get(document, properties, "ActualText")
        context.marked.push({
          replacement: if actual == @syntax.PdfNull {
            None
          } else {
            Some(pdf_text_string(actual))
          },
          span: context.spans.length(),
          chunk: context.chunks.length(),
          offset: context.units,
        })
      }
      Op_EMC => finish_marked(context)
      Op_MP(_) | Op_DP(_, _) | Op_ri(_) | Op_i(_) => ()
      Op_BX => compatibility += 1
      Op_EX => {
        guard compatibility > 0 else {
          @failure.reject("invalid-pdf", "PDF compatibility stack underflow")
        }
        compatibility -= 1
      }
      Op_Unknown(_) if compatibility > 0 => ()
      _ =>
        @failure.reject("unsupported-pdf", "Unsupported PDF content operator")
    }
  }
  guard stack.is_empty() &&
    compatibility == 0 &&
    context.marked.length() == marked_start else {
    @failure.reject("invalid-pdf", "Unbalanced PDF content state")
  }
  for _ in initial.clips..<state.clips {
    context.restore()
  }
}

///|
fn pdf_object_matrix(
  object : @syntax.PdfObject,
) -> @layout.Matrix raise @failure.Failure {
  if object == @syntax.PdfNull {
    return @layout.Matrix::identity()
  }
  guard object is PdfArray([a, b, c, d, e, f]) else {
    @failure.reject("invalid-pdf", "Invalid PDF matrix")
  }
  let result : @layout.Matrix = {
    a: number(a),
    b: number(b),
    c: number(c),
    d: number(d),
    e: number(e),
    f: number(f),
  }
  ignore(result.inverse())
  result
}
