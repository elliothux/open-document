///|
fn range_object_prefix(
  data : BytesView,
) -> (@syntax.PdfParsedIndirectObject, Int32?) raise @pdfcore.PdfError {
  let cursor = @pdfcore.byte_cursor_of_view(data)
  let tokens : Array[@syntax.PdfLexeme] = []
  for ;; {
    match @syntax.pdf_cursor_lex_token(cursor) {
      StopLexing | LexNone => break
      LexEndObj as token => {
        tokens.push(token)
        break
      }
      token => tokens.push(token)
    }
  }
  let (parsed, end, complete) = @syntax.pdf_parse_indirect_object_segment_at(
    tokens, 0,
  )
  if complete {
    return (parsed, None)
  }
  guard end == tokens.length() && parsed.object is @syntax.PdfDictionary(_) else {
    raise @pdfcore.PdfError::ParseEndObjectExpected
  }
  @pdfreader.pdf_cursor_consume_ascii(
    cursor,
    [115, 116, 114, 101, 97, 109],
    @pdfcore.PdfError::ParseStreamExpected,
  )
  while [0, 9, 12, 32].contains(cursor.peek_byte()) {
    cursor.nudge()
  }
  match cursor.input_byte() {
    13 => if cursor.peek_byte() == 10 { cursor.nudge() }
    10 => ()
    _ => raise @pdfcore.PdfError::ParseStreamExpected
  }
  (parsed, Some(cursor.absolute_position()))
}

///|
fn check_range_stream_footer(data : BytesView) -> Unit raise @pdfcore.PdfError {
  let footer = @pdfcore.byte_cursor_of_view(data)
  @syntax.pdf_cursor_drop_whitespace(footer)
  @pdfreader.pdf_cursor_consume_ascii(
    footer,
    [101, 110, 100, 115, 116, 114, 101, 97, 109],
    @pdfcore.PdfError::ParseEndStreamExpected,
  )
  guard @syntax.pdf_cursor_lex_token(footer) is LexEndObj else {
    raise @pdfcore.PdfError::ParseEndObjectExpected
  }
}

///|
fn PdfRangeReader::read_plain_object(
  self : PdfRangeReader,
  entry : @pdfreader.PdfClassicXRefEntry,
  seen : Map[Int32, Bool],
) -> @syntax.PdfObject raise {
  let offset = entry.offset
  let limit = (self.size - offset).min(self.budget.streamBytes)
  let (parsed, start) = for length = PdfIndexWindow.min(limit) {
    let data = self.read(offset, length)
    try range_object_prefix(data) catch {
      error if length == limit || @pdfcore.sdk_exhausted() => raise error
      _ => continue (length * 2).min(limit)
    } noraise {
      prefix => break prefix
    }
  }
  guard parsed.number == entry.object_number &&
    parsed.generation == entry.generation else {
    @failure.reject(
      "invalid-pdf",
      "PDF object header does not match xref",
      offset~,
    )
  }
  guard start is Some(start) else { return parsed.object }
  let start = offset + start
  let declared = match raw(parsed.object, "Length") {
    @syntax.PdfIndirect(number) => self.read_object_value(number, seen)
    length => length
  }
  guard declared is @syntax.PdfInteger(length) &&
    length >= 0 &&
    length < self.size - start else {
    @failure.reject(
      "invalid-pdf",
      "PDF stream length leaves the source",
      offset~,
    )
  }
  guard length <= self.budget.streamBytes else {
    @failure.reject(
      "limit-exceeded",
      "PDF source stream exceeds budget",
      offset~,
    )
  }
  let end = start + length
  check_range_stream_footer(
    self.read(end, (self.size - end).min(PdfIndexWindow)),
  )
  @pdfcore.sdk_decoded(length)
  let data = if length == 0 { b"" } else { self.read(start, length).to_owned() }
  @syntax.pdf_stream(parsed.object, @syntax.StreamGot(data))
}

///|
fn PdfRangeReader::read_object_value(
  self : PdfRangeReader,
  number : Int32,
  seen : Map[Int32, Bool],
) -> @syntax.PdfObject raise {
  @pdfcore.sdk_depth(seen.length())
  guard !seen.contains(number) &&
    self.entries.get(number) is Some({ in_use: true, .. } as entry) else {
    @failure.reject(
      "invalid-pdf",
      "Missing or cyclic PDF object: " + number.to_string(),
    )
  }
  seen[number] = true
  defer seen.remove(number)
  let value = if entry.object_stream is Some(reference) {
    let parent = reference.object_stream_number
    guard self.entries.get(parent)
      is Some({ in_use: true, object_stream: None, .. }) else {
      @failure.reject("invalid-pdf", "Missing PDF object stream")
    }
    let source = self.read_object_value(parent, seen)
    guard is_name(raw(source, "Type"), "ObjStm") &&
      @pdflite.pdf_decode_stream(source) is @syntax.PdfStreamObject(stream) &&
      raw(stream.dictionary, "N") is @syntax.PdfInteger(count) &&
      count >= 0 &&
      count <= self.budget.objects &&
      raw(stream.dictionary, "First") is @syntax.PdfInteger(first) else {
      @failure.reject("invalid-pdf", "Invalid PDF object stream dictionary")
    }
    let data = @syntax.pdf_stream_data_view(stream.data)
    let offsets = @pdfreader.pdf_object_stream_number_offsets(
      data, first, count,
    )
    let index = reference.index
    guard offsets.get(index) is Some((expected, relative)) && expected == number else {
      @failure.reject(
        "invalid-pdf", "PDF object stream index does not match xref",
      )
    }
    let end = @pdfreader.pdf_object_stream_end_offsets(
        offsets,
        data.length(),
        first,
      )[index]
    guard first >= 0 &&
      first <= data.length() &&
      relative >= 0 &&
      end >= relative &&
      end <= data.length() - first else {
      @failure.reject(
        "invalid-pdf", "PDF object stream member leaves its stream",
      )
    }
    @syntax.pdf_parse_object_from_view(data[first + relative:first + end])
  } else {
    self.read_plain_object(entry, seen)
  }
  validate_value(
    n => self.entries.get(n) is Some({ in_use: true, .. }),
    value,
    0,
  )
  value
}

///|
/// Load and validate an indirect object from a seekable unencrypted PDF.
pub fn PdfRangeReader::read_object(
  self : PdfRangeReader,
  number : Int32,
) -> @syntax.PdfObject raise @failure.Failure {
  ignore(self.unencrypted_catalog())
  pdf_bound(self.budget, () => self.read_object_value(number, Map([])))
}

///|
fn PdfRangeReader::unencrypted_catalog(
  self : PdfRangeReader,
) -> Int32 raise @failure.Failure {
  let root = self.catalog_number()
  guard self.trailer is Some(trailer) &&
    raw(trailer, "Encrypt") == @syntax.PdfNull else {
    @failure.reject(
      "unsupported-pdf", "Encrypted PDF requires the full-file reader",
    )
  }
  root
}
