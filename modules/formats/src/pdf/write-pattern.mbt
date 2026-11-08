///|
fn positioned_pattern(
  document : @pdflite.PdfDocument,
  period : Double,
  mask : Bytes,
  zero : String,
  one : String,
  matrix : @layout.Matrix,
  height : Double,
) -> @syntax.PdfObject raise {
  let rgb : Array[Byte] = []
  for row in mask {
    for x in 0..<8 {
      let color = if (row.to_int() & (1 << (7 - x))) == 0 { zero } else { one }
      for offset in [0, 2, 4] {
        rgb.push((channel(color, offset) * 255).round().to_int().to_byte())
      }
    }
  }
  let image = document.add_object(
    stream(@flate.pdf_flate_encode(Bytes::from_array(rgb)), [
      ("Type", tag("XObject")),
      ("Subtype", tag("Image")),
      ("Width", @syntax.PdfInteger(8)),
      ("Height", @syntax.PdfInteger(8)),
      ("BitsPerComponent", @syntax.PdfInteger(8)),
      ("ColorSpace", tag("DeviceRGB")),
      ("Interpolate", @syntax.PdfBoolean(false)),
      ("Filter", tag("FlateDecode")),
    ]),
  )
  let content = @pdflite.pdf_content_bytes_of_ops([
    @content.Op_cm({ a: period, b: 0, c: 0, d: period, e: 0, f: 0, }),
    @content.Op_Do(name("P")),
  ])
  @syntax.PdfIndirect(
    document.add_object(
      stream(content, [
        ("Type", tag("Pattern")),
        ("PatternType", @syntax.PdfInteger(1)),
        ("PaintType", @syntax.PdfInteger(1)),
        ("TilingType", @syntax.PdfInteger(1)),
        (
          "BBox",
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(0),
            @syntax.PdfReal(period),
            @syntax.PdfReal(period),
          ]),
        ),
        ("XStep", @syntax.PdfReal(period)),
        ("YStep", @syntax.PdfReal(period)),
        // Pattern coordinates follow the current frame; PDF's positive Y points upwards.
        (
          "Matrix",
          @syntax.PdfArray(
            [
              matrix.a,
              -matrix.b,
              -matrix.c,
              matrix.d,
              // Native PDF pattern origins retain five decimal places.
              (matrix.e * 100000).round() / 100000,
              ((height - matrix.f) * 100000).round() / 100000,
            ].map(value => @syntax.PdfReal(value)),
          ),
        ),
        (
          "Resources",
          dict([("XObject", dict([("P", @syntax.PdfIndirect(image))]))]),
        ),
      ]),
    ),
  )
}
