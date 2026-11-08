///|
fn image_stream_bytes(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  width : Int32,
  height : Int32,
  channels : Int32,
  bits : Int32,
) -> Bytes raise {
  let filter = get(document, object, "Filter")
  if is_name(filter, "JBIG2Decode") ||
    (
      filter is PdfArray([PdfNameObject(name)]) &&
      name == pdf_name("JBIG2Decode")
    ) {
    guard channels == 1 && bits == 1 else {
      @failure.reject("invalid-pdf", "JBIG2 requires one-bit grayscale samples")
    }
    return jbig2_samples(document, object, width, height)
  }
  let fax = is_name(filter, "CCITTFaxDecode") ||
    is_name(filter, "CCF") ||
    (
      filter is PdfArray([PdfNameObject(name)]) &&
      [pdf_name("CCITTFaxDecode"), pdf_name("CCF")].contains(name)
    )
  if !fax {
    return stream_bytes(document, object)
  }
  guard channels == 1 && bits == 1 else {
    @failure.reject("invalid-pdf", "CCITT requires one-bit grayscale samples")
  }
  let parameters = match get(document, object, "DecodeParms") {
    PdfArray([value]) => resolve(document, value)
    value => value
  }
  let parameters = if parameters == @syntax.PdfNull {
    dict([])
  } else {
    parameters
  }
  let columns = get(document, parameters, "Columns")
  let columns = if columns == @syntax.PdfNull { 1728 } else { integer(columns) }
  let rows = get(document, parameters, "Rows")
  let rows = if rows == @syntax.PdfNull { 0 } else { integer(rows) }
  guard columns == width && (rows == 0 || rows == height) else {
    @failure.reject("invalid-pdf", "CCITT geometry does not match the image")
  }
  guard raw(parameters, "DamagedRowsBeforeError") == @syntax.PdfNull ||
    get(document, parameters, "DamagedRowsBeforeError") == @syntax.PdfInteger(0) else {
    @failure.reject("unsupported-pdf", "Damaged CCITT rows are unsupported")
  }
  // Image height bounds decoding even when the fax stream omits an end marker.
  let parameters = parameters.with_entry(
    pdf_name("Rows"),
    @syntax.PdfInteger(height),
  )
  guard object.deep_copy() is PdfStreamObject(source) else {
    @failure.reject("invalid-pdf", "CCITT image requires a stream")
  }
  let copied = @syntax.pdf_stream(
    source.dictionary.with_entry(pdf_name("DecodeParms"), parameters),
    source.data,
  )
  let bytes = document.pdf_decode_stream(copied).stream_bytes()
  guard bytes.length() == (width + 7) / 8 * height else {
    @failure.reject(
      "invalid-pdf", "CCITT sample count does not match image dimensions",
    )
  }
  bytes
}
