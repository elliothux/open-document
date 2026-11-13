///|
const PdfIndexWindow : Int32 = 4096

///|
const PdfTailLimit : Int32 = 65536

///|
/// A seekable PDF source. The host keeps its length and bytes stable.
pub struct PdfRangeReader {
  priv size : Int32
  priv read_at : (Int32, Int32) -> BytesView raise @failure.Failure
  priv budget : PdfBudget
  priv entries : Map[Int32, @pdfreader.PdfClassicXRefEntry]
  priv sections : Map[Int32, Bool]
  priv mut revisions : Int32
  priv mut revision : @pdfreader.PdfXRefSection?
  priv mut next : Int32?
  priv mut trailer : @syntax.PdfObject?
  priv mut version : @pdfreader.PdfVersion?
  priv mut tail : (Int32, BytesView)?
  priv mut window : Int32
  priv mut pages : Array[SourcePage]?
  priv page_index_objects : Map[Int32, @syntax.PdfObject]
  priv mut index_bytes : Int32
}

///|
/// Create a reader without fetching any bytes. A failed range can be supplied
/// by the host before retrying the same operation on this reader.
pub fn PdfRangeReader::new(
  size : Int32,
  read_at : (Int32, Int32) -> BytesView raise @failure.Failure,
  budget : PdfBudget,
) -> PdfRangeReader raise @failure.Failure {
  budget.validate(PdfBudget::range_default())
  guard size <= budget.fileBytes else {
    @failure.reject("limit-exceeded", "PDF input exceeds budget")
  }
  guard size >= 8 else { @failure.reject("invalid-pdf", "Missing PDF header") }
  {
    size,
    read_at,
    budget,
    entries: Map([]),
    sections: Map([]),
    revisions: 0,
    revision: None,
    next: None,
    trailer: None,
    version: None,
    tail: None,
    window: PdfIndexWindow,
    pages: None,
    page_index_objects: Map([]),
    index_bytes: 0,
  }
}

///|
fn PdfRangeReader::read(
  self : PdfRangeReader,
  offset : Int32,
  length : Int32,
) -> BytesView raise @failure.Failure {
  guard offset >= 0 &&
    offset <= self.size &&
    length > 0 &&
    length <= self.size - offset else {
    @failure.reject("invalid-pdf", "PDF byte range leaves the source", offset~)
  }
  if self.tail is Some((start, tail)) && offset >= start {
    return tail[offset - start:offset - start + length]
  }
  let bytes = (self.read_at)(offset, length)
  guard bytes.length() == length else {
    @failure.reject("truncated-source", "Incomplete PDF source range", offset~)
  }
  bytes
}

///|
fn PdfRangeReader::find_tail(
  self : PdfRangeReader,
) -> Unit raise @failure.Failure {
  for ;; {
    let limit = PdfTailLimit.min(self.size)
    let length = self.window.min(limit)
    let offset = self.size - length
    let tail = self.read(offset, length)
    let result = @pdfreader.pdf_read_startxref_position(tail) catch {
      @pdfcore.PdfError::StartXRefExpected if length < limit => {
        self.window = (length * 2).min(limit)
        continue
      }
      _ => @failure.reject("invalid-pdf", "Invalid PDF startxref", offset~)
    }
    self.tail = Some((offset, tail))
    self.next = Some(result)
    self.window = PdfIndexWindow
    break
  }
}

///|
fn parse_range_xref(
  data : BytesView,
) -> @pdfreader.PdfXRefSection raise @pdfcore.PdfError {
  let cursor = @pdfcore.byte_cursor_of_view(data)
  @syntax.pdf_cursor_drop_whitespace(cursor)
  let offset = cursor.absolute_position()
  if @syntax.pdf_cursor_matches_ascii_at(cursor, offset, [120, 114, 101, 102]) {
    @pdfcore.sdk_check(data.length() / 16 + 1)
    guard @pdfcore.pdf_find_ascii_from(data, offset + 4, [
        116, 114, 97, 105, 108, 101, 114,
      ]) >=
      0 else {
      raise @pdfcore.PdfError::TrailerExpected
    }
    return {
      entries: @pdfreader.pdf_cursor_read_classic_xref_entries(cursor),
      trailer: @pdfreader.pdf_cursor_read_trailer_dictionary(cursor),
      stream_object_number: None,
      stream_object_offset: None,
    }
  }
  let (parsed, start) = range_object_prefix(data)
  guard start is Some(start) &&
    @pdfreader.pdf_reader_xref_stream_type_ok(parsed.object) &&
    raw(parsed.object, "Length") is @syntax.PdfInteger(length) &&
    length >= 0 &&
    length < data.length() - start else {
    raise @pdfcore.PdfError::XRefExpected
  }
  let end = start + length
  check_range_stream_footer(data[end:])
  @pdfcore.sdk_decoded(length)
  let source = @syntax.pdf_stream(
    parsed.object,
    @syntax.StreamGot(data[start:end].to_owned()),
  )
  guard @pdflite.pdf_decode_stream(source) is @syntax.PdfStreamObject(stream) else {
    raise @pdfcore.PdfError::XRefExpected
  }
  let widths = @pdfreader.pdf_xref_stream_widths(stream.dictionary)
  let pairs = @pdfreader.pdf_xref_stream_index_pairs(stream.dictionary)
  let entries = @pdfreader.pdf_xref_stream_entries(
    @syntax.pdf_stream_data_bytes(stream.data),
    widths,
    pairs,
  )
  {
    entries,
    trailer: @pdfreader.pdf_reader_stream_dictionary_without_xref_keys(
      stream.dictionary,
    ),
    stream_object_number: Some(parsed.number),
    stream_object_offset: Some(offset),
  }
}

///|
fn PdfRangeReader::read_xref(
  self : PdfRangeReader,
  offset : Int32,
) -> @pdfreader.PdfXRefSection raise @failure.Failure {
  guard offset > 0 && offset < self.size && !self.sections.contains(offset) else {
    @failure.reject(
      "invalid-pdf",
      "Invalid or cyclic PDF cross-reference offset",
      offset~,
    )
  }
  let limit = (self.size - offset).min(self.budget.streamBytes)
  if self.revisions == 0 &&
    self.revision is None &&
    self.size - offset <= PdfTailLimit {
    self.window = limit
  }
  for ;; {
    let length = self.window.min(limit)
    guard length <= self.budget.decodedBytes - self.index_bytes else {
      @failure.reject(
        "limit-exceeded",
        "PDF cross-reference bytes exceed budget",
        offset~,
      )
    }
    let data = self.read(offset, length)
    self.index_bytes += length
    let result = pdf_bound(self.budget, () => {
      try parse_range_xref(data) catch {
        error if length == limit => raise error
        _ => None
      } noraise {
        section => Some(section)
      }
    })
    match result {
      Some(section) => {
        self.window = PdfIndexWindow
        return section
      }
      None => self.window = (length * 2).min(limit)
    }
  }
}

///|
fn PdfRangeReader::merge_xref(
  self : PdfRangeReader,
  section : @pdfreader.PdfXRefSection,
) -> Unit raise @failure.Failure {
  for entry in section.entries {
    let number = entry.object_number
    if self.entries.contains(number) {
      continue
    }
    guard number >= 0 &&
      number <= self.budget.objectNumber &&
      self.entries.length() < self.budget.objects + 1 else {
      @failure.reject(
        "limit-exceeded", "PDF cross-reference entry exceeds budget",
      )
    }
    if entry.object_stream is Some(reference) {
      guard reference.object_stream_number > 0 &&
        reference.object_stream_number <= self.budget.objectNumber &&
        reference.index >= 0 &&
        reference.index < self.budget.objects else {
        @failure.reject("invalid-pdf", "Invalid PDF object stream reference")
      }
      self.entries[number] = { ..entry, generation: 0, }
    } else {
      guard !entry.in_use ||
        (
          entry.offset > 0 &&
          entry.offset < self.size &&
          entry.generation >= 0 &&
          entry.generation <= 65535
        ) else {
        @failure.reject(
          "invalid-pdf",
          "Invalid PDF cross-reference entry",
          offset=entry.offset,
        )
      }
      self.entries[number] = entry
    }
  }
}

///|
/// Read the xref chain and return the catalog object number. No page object is
/// parsed until it is requested separately.
pub fn PdfRangeReader::catalog_number(
  self : PdfRangeReader,
) -> Int32 raise @failure.Failure {
  if self.version is None {
    if self.tail is None {
      self.find_tail()
    }
    let cursor = @pdfcore.byte_cursor_of_view(
      self.read(0, PdfIndexWindow.min(self.size)),
    )
    let version = pdf_bound(self.budget, () => {
      @pdfreader.pdf_read_header_from_cursor(cursor)
    })
    guard cursor.absolute_position() > 0 &&
      (
        (version.major == 1 && version.minor >= 0 && version.minor <= 7) ||
        (version.major == 2 && version.minor == 0)
      ) else {
      @failure.reject("invalid-pdf", "Invalid PDF header version")
    }
    self.version = Some(version)
  }
  while self.next is Some(offset) {
    guard self.revisions < self.budget.revisions else {
      @failure.reject(
        "limit-exceeded", "PDF cross-reference revisions exceed budget",
      )
    }
    let section = if self.revision is Some(section) {
      section
    } else {
      let section = self.read_xref(offset)
      self.sections[offset] = true
      self.revision = Some(section)
      section
    }
    let (previous, hybrid) = pdf_bound(self.budget, () => {
      (
        @pdfreader.pdf_trailer_prev_position(section.trailer),
        @pdfreader.pdf_trailer_xref_stream_position(section.trailer),
      )
    })
    if hybrid is Some(position) {
      let supplement = self.read_xref(position)
      guard supplement.stream_object_number is Some(_) else {
        @failure.reject(
          "invalid-pdf",
          "PDF XRefStm must point to an xref stream",
          offset=position,
        )
      }
      self.sections[position] = true
      self.merge_xref(section)
      self.merge_xref(supplement)
    } else {
      self.merge_xref(section)
    }
    if self.trailer is None {
      self.trailer = Some(section.trailer)
    }
    self.revisions += 1
    self.revision = None
    self.next = previous
  }
  guard self.trailer is Some(trailer) &&
    raw(trailer, "Root") is @syntax.PdfIndirect(number) &&
    self.entries.get(number) is Some({ in_use: true, .. }) else {
    @failure.reject("invalid-pdf", "PDF cross-reference has no catalog")
  }
  self.tail = None
  number
}
