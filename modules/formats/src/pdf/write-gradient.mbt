///|
fn gradient_shading(stops : Array[@layout.GradientStop]) -> @syntax.PdfObject {
  let points : Array[@layout.GradientStop] = [
    { position: 0, color: stops[0].color, },
    ..stops,
    { position: 1, color: stops.last().unwrap().color, },
  ]
  let functions : Array[@syntax.PdfObject] = []
  let bounds : Array[@syntax.PdfObject] = []
  for index in 0..<(points.length() - 1) {
    let start = points[index]
    let end = points[index + 1]
    // Zero-length intervals are hard color transitions, not interpolation functions.
    if start.position == end.position {
      continue
    }
    if !functions.is_empty() {
      bounds.push(@syntax.PdfReal(start.position))
    }
    functions.push(gradient_interpolation(start.color, end.color))
  }
  dict([
    ("ShadingType", @syntax.PdfInteger(2)),
    ("ColorSpace", tag("DeviceRGB")),
    ("Coords", @syntax.PdfArray([0, 0, 1, 0].map(v => @syntax.PdfInteger(v)))),
    (
      "Extend",
      @syntax.PdfArray([@syntax.PdfBoolean(true), @syntax.PdfBoolean(true)]),
    ),
    (
      "Function",
      dict([
        ("FunctionType", @syntax.PdfInteger(3)),
        (
          "Domain",
          @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
        ),
        ("Bounds", @syntax.PdfArray(bounds)),
        (
          "Encode",
          @syntax.PdfArray(
            functions
            .map(_ => [@syntax.PdfInteger(0), @syntax.PdfInteger(1)])
            .flatten(),
          ),
        ),
        ("Functions", @syntax.PdfArray(functions)),
      ]),
    ),
  ])
}

///|
fn gradient_interpolation(start : String, end : String) -> @syntax.PdfObject {
  dict([
    ("FunctionType", @syntax.PdfInteger(2)),
    ("Domain", @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)])),
    (
      "C0",
      @syntax.PdfArray([0, 2, 4].map(i => @syntax.PdfReal(channel(start, i)))),
    ),
    (
      "C1",
      @syntax.PdfArray([0, 2, 4].map(i => @syntax.PdfReal(channel(end, i)))),
    ),
    ("N", @syntax.PdfInteger(1)),
  ])
}
