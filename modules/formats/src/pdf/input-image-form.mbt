///|
fn PdfTransaction::image_form(
  self : PdfTransaction,
  width : Int32,
  height : Int32,
  rgba : Bytes,
) -> @syntax.PdfObject raise {
  guard width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() * 4 == rgba.length().to_int64() &&
    rgba.length() <= 16777216 else {
    @failure.reject("invalid-image", "PDF image requires bounded RGBA pixels")
  }
  let rgb = Bytes::makei(width * height * 3, i => rgba[i / 3 * 4 + i % 3])
  let alpha = Bytes::makei(width * height, i => rgba[i * 4 + 3])
  let entries : Array[(String, @syntax.PdfObject)] = [
    ("Type", tag("XObject")),
    ("Subtype", tag("Image")),
    ("Width", @syntax.PdfInteger(width)),
    ("Height", @syntax.PdfInteger(height)),
    ("ColorSpace", tag("DeviceRGB")),
    ("BitsPerComponent", @syntax.PdfInteger(8)),
  ]
  if alpha.iter().any(value => value != 255) {
    entries.push(
      (
        "SMask",
        self.add(
          stream(alpha, [
            ("Type", tag("XObject")),
            ("Subtype", tag("Image")),
            ("Width", @syntax.PdfInteger(width)),
            ("Height", @syntax.PdfInteger(height)),
            ("ColorSpace", tag("DeviceGray")),
            ("BitsPerComponent", @syntax.PdfInteger(8)),
          ]),
        ),
      ),
    )
  }
  let image = self.add(stream(rgb, entries))
  let form = appearance_stream(
    @pdflite.pdf_content_bytes_of_ops([
      @content.Op_q,
      @content.Op_cm({
        a: width.to_double(),
        b: 0,
        c: 0,
        d: height.to_double(),
        e: 0,
        f: 0,
      }),
      @content.Op_Do(pdf_name("Image")),
      @content.Op_Q,
    ]),
    width.to_double(),
    height.to_double(),
    dict([("XObject", dict([("Image", image)]))]),
  )
  guard form is PdfStreamObject(value) else { abort("Expected image Form") }
  let form = self.add(
    @syntax.pdf_stream(
      value.dictionary.with_entry(pdf_name("ODKind"), tag("Image")),
      value.data,
    ),
  )
  form
}
