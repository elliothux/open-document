///|
fn gradient_shading(
  stops : Array[@layout.GradientStop],
  alpha~ : Bool = false,
  radial~ : Bool = false,
) -> @syntax.PdfObject {
  let points : Array[@layout.GradientStop] = [
    { ..stops[0], position: 0, },
    ..stops,
    { ..stops.last().unwrap(), position: 1, },
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
    functions.push(gradient_interpolation(start, end, alpha~))
  }
  dict([
    ("ShadingType", @syntax.PdfInteger(if radial { 3 } else { 2 })),
    ("ColorSpace", tag(if alpha { "DeviceGray" } else { "DeviceRGB" })),
    (
      "Coords",
      @syntax.PdfArray(
        (if radial {
          [0.5, 0.5, 0.0, 0.5, 0.5, 0.5]
        } else {
          [0.0, 0.0, 1.0, 0.0]
        }).map(v => @syntax.PdfReal(v)),
      ),
    ),
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
fn gradient_interpolation(
  start : @layout.GradientStop,
  end : @layout.GradientStop,
  alpha~ : Bool,
) -> @syntax.PdfObject {
  dict([
    ("FunctionType", @syntax.PdfInteger(2)),
    ("Domain", @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)])),
    (
      "C0",
      @syntax.PdfArray(
        (if alpha {
          [start.opacity]
        } else {
          [0, 2, 4].map(i => channel(start.color, i))
        }).map(value => @syntax.PdfReal(value)),
      ),
    ),
    (
      "C1",
      @syntax.PdfArray(
        (if alpha {
          [end.opacity]
        } else {
          [0, 2, 4].map(i => channel(end.color, i))
        }).map(value => @syntax.PdfReal(value)),
      ),
    ),
    ("N", @syntax.PdfInteger(1)),
  ])
}

///|
fn gradient_mask(
  document : @pdflite.PdfDocument,
  stops : Array[@layout.GradientStop],
  radial~ : Bool = false,
) -> @syntax.PdfObject {
  let shading = @syntax.PdfIndirect(
    document.add_object(gradient_shading(stops, alpha=true, radial~)),
  )
  let group = document.add_object(
    stream(@utf8.encode("/M sh\n"), [
      ("Type", tag("XObject")),
      ("Subtype", tag("Form")),
      (
        "BBox",
        @syntax.PdfArray([0, 0, 1, 1].map(value => @syntax.PdfInteger(value))),
      ),
      (
        "Group",
        dict([
          ("S", tag("Transparency")),
          ("CS", tag("DeviceGray")),
          ("I", @syntax.PdfBoolean(true)),
        ]),
      ),
      ("Resources", dict([("Shading", dict([("M", shading)]))])),
    ]),
  )
  dict([
    ("Type", tag("ExtGState")),
    (
      "SMask",
      dict([
        ("S", tag("Luminosity")),
        ("G", @syntax.PdfIndirect(group)),
        ("BC", @syntax.PdfArray([@syntax.PdfInteger(0)])),
      ]),
    ),
  ])
}
