///|
fn shading_function_work(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  depth : Int32,
) -> (Int32, @syntax.PdfObject) raise {
  guard depth < 8 else {
    @failure.reject(
      "limit-exceeded", "PDF shading function depth exceeds budget",
    )
  }
  @pdfcore.sdk_check(1)
  let object = resolve(document, object)
  guard object is (PdfDictionary(_) | PdfStreamObject(_)) else {
    @failure.reject(
      "unsupported-pdf", "PDF shading requires interpolation functions",
    )
  }
  for key in ["Domain", "Range", "C0", "C1", "Bounds", "Encode"] {
    let value = get(document, object, key)
    if value != @syntax.PdfNull {
      guard value is PdfArray(values) && values.length() <= 64 else {
        @failure.reject(
          "limit-exceeded", "PDF shading function array exceeds budget",
        )
      }
      for value in values {
        ignore(number(resolve(document, value)))
      }
    }
  }
  match integer(get(document, object, "FunctionType")) {
    0 => {
      guard object is PdfStreamObject(_) &&
        get(document, object, "Size") is PdfArray([PdfInteger(count)]) &&
        count >= 2 &&
        count <= 4096 &&
        [@syntax.PdfNull, @syntax.PdfInteger(1)].contains(
          get(document, object, "Order"),
        ) &&
        get(document, object, "Range") is PdfArray(range) &&
        [2, 6].contains(range.length()) &&
        [1, 2, 4, 8, 12, 16].contains(
          integer(get(document, object, "BitsPerSample")),
        ) else {
        @failure.reject(
          "unsupported-pdf", "PDF sampled shading requires bounded one-dimensional linear samples",
        )
      }
      let bits = integer(get(document, object, "BitsPerSample"))
      let bytes = stream_bytes(document, object)
      guard bytes.length() == (count * range.length() / 2 * bits + 7) / 8 else {
        @failure.reject(
          "invalid-pdf", "PDF shading sample count does not match dimensions",
        )
      }
      @pdfcore.sdk_check(count * range.length())
      let dictionary = match object {
        PdfStreamObject(stream) => stream.dictionary
        _ => @syntax.PdfNull
      }
      // Parse the checked decoded bytes once, while keeping the source stream untouched.
      (
        1,
        @syntax.pdf_stream(
          dictionary
          .with_entry(pdf_name("Filter"), @syntax.PdfNull)
          .with_entry(pdf_name("DecodeParms"), @syntax.PdfNull)
          .with_entry(pdf_name("Length"), @syntax.PdfInteger(bytes.length())),
          @syntax.StreamGot(bytes),
        ),
      )
    }
    2 => {
      guard object is PdfDictionary(_) else {
        @failure.reject(
          "invalid-pdf", "Interpolation function requires a dictionary",
        )
      }
      (1, object)
    }
    3 => {
      guard object is PdfDictionary(_) else {
        @failure.reject(
          "invalid-pdf", "Stitching function requires a dictionary",
        )
      }
      guard get(document, object, "Functions") is PdfArray(functions) &&
        !functions.is_empty() &&
        functions.length() <= 32 else {
        @failure.reject(
          "limit-exceeded", "PDF shading function count exceeds budget",
        )
      }
      let mut work = 1
      let prepared : Array[@syntax.PdfObject] = []
      for function in functions {
        let (count, child) = shading_function_work(
          document,
          function,
          depth + 1,
        )
        work += count
        prepared.push(child)
        guard work <= 32 else {
          @failure.reject(
            "limit-exceeded", "PDF shading function count exceeds budget",
          )
        }
      }
      (
        work,
        object.with_entry(pdf_name("Functions"), @syntax.PdfArray(prepared)),
      )
    }
    _ =>
      @failure.reject(
        "unsupported-pdf", "PDF shading requires linear interpolation functions",
      )
  }
}

///|
fn shading_function_points(
  function : @pdflite.PdfFunction,
  components : Int32,
) -> Array[(Double, Array[Double])] raise {
  guard function.domain is [first, last] && first < last else {
    @failure.reject(
      "invalid-pdf", "PDF shading function requires one ordered domain",
    )
  }
  let points : Array[(Double, Array[Double])] = match function.func {
    PdfFunctionSampled(value) => {
      guard value.size is [count] &&
        count >= 2 &&
        count <= 4096 &&
        value.order == 1 &&
        value.encode is [a, b] &&
        a != b &&
        a >= 0 &&
        b >= 0 &&
        a <= (count - 1).to_double() &&
        b <= (count - 1).to_double() else {
        @failure.reject("unsupported-pdf", "Invalid PDF sampled shading domain")
      }
      let positions = Array::makei(count, i => {
        first + (i.to_double() - a) / (b - a) * (last - first)
      }).filter(t => t >= first && t <= last)
      let positions = if a < b { positions } else { positions.rev() }
      [
        (first, function.eval([first])),
        ..positions.map(t => (t, function.eval([t]))),
        (last, function.eval([last])),
      ]
    }
    PdfFunctionInterpolation(value) => {
      guard value.c0.length() == components &&
        value.c1.length() == components &&
        !value.n.is_nan() &&
        !value.n.is_inf() else {
        @failure.reject(
          "unsupported-pdf", "Invalid PDF shading component interpolation",
        )
      }
      let unclamped = { ..function, range: None, }
      if value.n == 1 {
        [(first, unclamped.eval([first])), (last, unclamped.eval([last]))]
      } else {
        fn evaluate(t : Double) -> Array[Double] raise {
          @pdfcore.sdk_check(components + 1)
          let values = unclamped.eval([t])
          guard values.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v <= 1) else {
            @failure.reject(
              "unsupported-pdf", "PDF shading requires bounded color components",
            )
          }
          values
        }
        let left = evaluate(first)
        let right = evaluate(last)
        let points = [(first, left)]
        fn subdivide(
          a : Double,
          va : Array[Double],
          b : Double,
          vb : Array[Double],
          depth : Int32,
        ) -> Unit raise {
          guard depth < 24 else {
            @failure.reject(
              "limit-exceeded", "PDF shading interpolation exceeds subdivision budget",
            )
          }
          @pdfcore.sdk_decoded(3 * (components + 1) * 8)
          let probes = [0.25, 0.5, 0.75].map(t => evaluate(a + (b - a) * t))
          let curved = probes
            .mapi((i, values) => {
              values
              .mapi((c, v) => {
                (v - (va[c] + (vb[c] - va[c]) * (i + 1).to_double() / 4.0)).abs() >
                1.0 / 4096.0
              })
              .any(v => v)
            })
            .any(v => v)
          if curved {
            let middle = (a + b) / 2.0
            subdivide(a, va, middle, probes[1], depth + 1)
            subdivide(middle, probes[1], b, vb, depth + 1)
          } else {
            guard points.length() < 4096 else {
              @failure.reject(
                "limit-exceeded", "PDF shading interpolation exceeds point budget",
              )
            }
            points.push((b, vb))
          }
        }
        subdivide(first, left, last, right, 0)
        points
      }
    }
    PdfFunctionStitching(value) => {
      let edges = [first, ..value.bounds, last]
      guard edges
        .mapi((index, edge) => index == 0 || edge > edges[index - 1])
        .all(x => x) else {
        @failure.reject(
          "invalid-pdf", "PDF shading function bounds must be ordered",
        )
      }
      let result : Array[(Double, Array[Double])] = []
      for index, child in value.functions {
        let child_points = shading_function_points(child, components)
        let a = value.stitch_encode[index * 2]
        let b = value.stitch_encode[index * 2 + 1]
        let selected = if a == b {
          [(a, child.eval([a])), (b, child.eval([b]))]
        } else {
          let middle = child_points.filter(point => {
            point.0 >= a.min(b) && point.0 <= a.max(b)
          })
          let ordered = if a < b { middle } else { middle.rev() }
          [(a, child.eval([a])), ..ordered, (b, child.eval([b]))]
        }
        for point_index, point in selected {
          let position = if a == b {
            if point_index == 0 {
              edges[index]
            } else {
              edges[index + 1]
            }
          } else {
            edges[index] +
            (point.0 - a) / (b - a) * (edges[index + 1] - edges[index])
          }
          if result.last() != Some((position, point.1)) {
            result.push((position, point.1))
          }
        }
        guard result.length() <= 4096 else {
          @failure.reject("limit-exceeded", "PDF shading stops exceed budget")
        }
      }
      result
    }
    _ =>
      @failure.reject(
        "unsupported-pdf", "PDF shading requires linear interpolation functions",
      )
  }
  for (_, values) in points {
    guard values.length() == components &&
      values.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v <= 1) else {
      @failure.reject(
        "unsupported-pdf", "PDF shading requires bounded color components",
      )
    }
    if function.range is Some(range) {
      guard range.length() == components * 2 &&
        values
        .mapi((index, value) => {
          value >= range[index * 2] && value <= range[index * 2 + 1]
        })
        .all(x => x) else {
        @failure.reject(
          "unsupported-pdf", "PDF shading function range clips interpolation",
        )
      }
    }
  }
  points
}

///|
fn ContentContext::axial_shading(
  self : ContentContext,
  resources : @syntax.PdfObject,
  name : @pdfcore.PdfName,
  state : GraphicsState,
) -> Unit raise {
  let document = self.session.document
  let object = get(
    document,
    get(document, resources, "Shading"),
    @utf8.decode_lossy(name.bytes())[1:].to_owned(),
  )
  guard object is PdfDictionary(_) &&
    integer(get(document, object, "ShadingType")) == 2 else {
    @failure.reject("unsupported-pdf", "Only axial PDF shading is supported")
  }
  guard get(document, object, "Coords") is PdfArray([x0, y0, x1, y1]) else {
    @failure.reject(
      "invalid-pdf", "PDF axial shading requires four coordinates",
    )
  }
  let (x0, y0, x1, y1) = (number(x0), number(y0), number(x1), number(y1))
  let space = self.color_space(resources, get(document, object, "ColorSpace"))
  guard space is (GrayColor | RgbColor | IccColor(_)) else {
    @failure.reject(
      "unsupported-pdf", "PDF shading requires RGB or gray interpolation",
    )
  }
  let domain = match get(document, object, "Domain") {
    PdfNull => (0.0, 1.0)
    PdfArray([a, b]) => (number(a), number(b))
    _ => @failure.reject("invalid-pdf", "Invalid PDF shading domain")
  }
  guard domain.0 < domain.1 else {
    @failure.reject("invalid-pdf", "PDF shading domain must be ordered")
  }
  let (extend_first, extend_last) = match get(document, object, "Extend") {
    PdfNull => (false, false)
    PdfArray([PdfBoolean(a), PdfBoolean(b)]) => (a, b)
    _ => @failure.reject("invalid-pdf", "Invalid PDF shading extension flags")
  }
  guard [@syntax.PdfNull, @syntax.PdfBoolean(false), @syntax.PdfBoolean(true)].contains(
    get(document, object, "AntiAlias"),
  ) else {
    @failure.reject("invalid-pdf", "Invalid PDF shading antialias flag")
  }
  let source = get(document, object, "Function")
  let source = match source {
    PdfArray([single]) => single
    PdfArray(_) =>
      @failure.reject(
        "unsupported-pdf", "Separate PDF shading component functions are unsupported",
      )
    _ => source
  }
  let (_, prepared) = shading_function_work(document, source, 0)
  let function = document.parse_function(prepared)
  let knots = shading_function_points(function, space.components())
  let points = [
    (domain.0, function.eval([domain.0])),
    ..knots.filter(p => p.0 >= domain.0 && p.0 <= domain.1),
    (domain.1, function.eval([domain.1])),
  ]
  let bbox = match get(document, object, "BBox") {
    PdfNull => None
    value => Some(rectangle(value))
  }
  // The sh operator ignores Background; that entry applies to shading patterns.
  let dx = x1 - x0
  let dy = y1 - y0
  if dx == 0 && dy == 0 {
    return
  }
  let axis = state.matrix.then({ a: dx, b: dy, c: -dy, d: dx, e: x0, f: y0, })
  let inverse = axis.inverse()
  let corners = [
    (0.0, 0.0),
    (self.page.width, 0.0),
    (0.0, self.page.height),
    (self.page.width, self.page.height),
  ].map(p => checked_point(inverse, p.0, p.1))
  let left = corners.fold(init=corners[0].0, (a, p) => a.min(p.0))
  let right = corners.fold(init=corners[0].0, (a, p) => a.max(p.0))
  let top = corners.fold(init=corners[0].1, (a, p) => a.min(p.1))
  let bottom = corners.fold(init=corners[0].1, (a, p) => a.max(p.1))
  let left = if extend_first { left.min(0) } else { 0.0 }
  let right = if extend_last { right.max(1) } else { 1.0 }
  if right <= left || bottom <= top {
    return
  }
  let stops : Array[@layout.GradientStop] = []
  for point in shading_color_points(points, space) {
    let position = ((point.0 - domain.0) / (domain.1 - domain.0) - left) /
      (right - left)
    let stop : @layout.GradientStop = { position, color: point.1, opacity: 1, }
    if stops.last() != Some(stop) {
      stops.push(stop)
    }
  }
  guard stops.length() <= 32 else {
    @failure.reject("limit-exceeded", "PDF shading stops exceed budget")
  }
  @layout.validate_gradient_stops(stops)
  guard self.nesting + (if bbox is Some(_) { 2 } else { 1 }) <= 32 &&
    self.commands.length() <= 1048568 else {
    @failure.reject(
      "limit-exceeded", "PDF shading drawing stack exceeds budget",
    )
  }
  if bbox is Some((x, y, right, bottom)) {
    let path = [
      @layout.Move(x, y),
      @layout.Line(right, y),
      @layout.Line(right, bottom),
      @layout.Line(x, bottom),
      @layout.Close,
    ]
    self.scope(@layout.ClipPath(path_in(path, state.matrix), false))
  }
  self.scope(@layout.Transform(axis))
  self.commands.push(@layout.Style(state.style))
  self.commands.push(
    @layout.GradientRect(
      { x: left, y: top, width: right - left, height: bottom - top, },
      stops,
    ),
  )
  self.restore()
  if bbox is Some(_) {
    self.restore()
  }
}
