///|
fn name(text : String) -> @pdfcore.PdfName {
  @pdfcore.pdf_name_of_bytes(@utf8.encode(text))
}

///|
fn dict(entries : Array[(String, @syntax.PdfObject)]) -> @syntax.PdfObject {
  @syntax.PdfDictionary(entries.map(pair => (name(pair.0), pair.1)))
}

///|
fn tag(text : String) -> @syntax.PdfObject {
  @syntax.PdfNameObject(name(text))
}

///|
fn stream(
  bytes : Bytes,
  entries : Array[(String, @syntax.PdfObject)],
) -> @syntax.PdfObject {
  @syntax.pdf_stream(dict(entries), @syntax.StreamGot(bytes))
}

///|
fn hex16(value : Int) -> String {
  let digits = "0123456789ABCDEF"
  let result = StringBuilder()
  for shift in [12, 8, 4, 0] {
    result.write_char(digits[(value >> shift) & 15].to_char().unwrap())
  }
  result.to_string()
}

///|
fn unicode_hex(text : String) -> String {
  let result = StringBuilder()
  for i in 0..<text.length() {
    result.write_string(hex16(text[i].to_int()))
  }
  result.to_string()
}

///|
fn utf16_bytes(text : String) -> Bytes {
  let result : Array[Byte] = [0xfe, 0xff]
  for i in 0..<text.length() {
    result.push((text[i].to_int() >> 8).to_byte())
    result.push((text[i].to_int() & 255).to_byte())
  }
  Bytes::from_array(result)
}

///|
fn channel(color : String, offset : Int) -> Double {
  let digits = "0123456789abcdef"
  let low = color.to_lower()
  let a = digits.find(low[offset:offset + 1]).unwrap()
  let b = digits.find(low[offset + 1:offset + 2]).unwrap()
  (a * 16 + b).to_double() / 255
}
