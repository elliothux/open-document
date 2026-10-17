///|
fn gradient_shading(start : String, end : String) -> @syntax.PdfObject {
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
        ("FunctionType", @syntax.PdfInteger(2)),
        (
          "Domain",
          @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
        ),
        (
          "C0",
          @syntax.PdfArray(
            [0, 2, 4].map(i => @syntax.PdfReal(channel(start, i))),
          ),
        ),
        (
          "C1",
          @syntax.PdfArray([0, 2, 4].map(i => @syntax.PdfReal(channel(end, i)))),
        ),
        ("N", @syntax.PdfInteger(1)),
      ]),
    ),
  ])
}
