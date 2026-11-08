///|
fn recover_classic_xref(
  bytes : BytesView,
) -> @pdflite.PdfDocument? raise @pdfcore.PdfError {
  guard bytes.has_prefix(b"%PDF-") else { return None }
  let end = @pdfcore.pdf_startxref_search_view(bytes).length()
  guard end + 5 <= bytes.length() &&
    bytes[end:end + 5] == b"%%EOF" &&
    bytes[end + 5:]
    .iter()
    .all(byte => @pdfcore.pdf_is_whitespace_byte(byte.to_int())) else {
    return None
  }
  let tail = (end - 128).max(0)
  let marker = @pdfcore.pdf_find_last_ascii(bytes[tail:end], [
    115, 116, 97, 114, 116, 120, 114, 101, 102,
  ])
  guard marker >= 0 else { return None }
  let marker = tail + marker
  guard @pdfcore.pdf_split_whitespace_tokens(bytes[marker:end])
    is [keyword, offset] &&
    keyword == b"startxref" &&
    offset.iter().all(byte => @pdfcore.pdf_is_digit_byte(byte.to_int())) else {
    return None
  }
  let floor = (marker - 65536).max(1)
  let xref = for index = marker - 5; index >= floor; index = index - 1 {
    if (bytes[index - 1] == b'\n' || bytes[index - 1] == b'\r') &&
      bytes[index:index + 4] == b"xref" &&
      @pdfcore.pdf_is_whitespace_byte(bytes[index + 4].to_int()) {
      break index
    }
  } nobreak {
    return None
  }
  guard @pdfcore.pdf_parse_ascii_int_view(offset) != xref else { return None }
  let cursor = @pdfcore.byte_cursor_of_view(bytes[:marker])
  cursor.seek_absolute(xref)
  let entries = @pdfreader.pdf_cursor_read_classic_xref_entries(cursor)
  let trailer = @pdfreader.pdf_cursor_read_trailer_dictionary(cursor)
  @syntax.pdf_cursor_drop_whitespace(cursor)
  guard cursor.absolute_position() == marker &&
    raw(trailer, "Size") is @syntax.PdfInteger(size) &&
    size == entries.length() &&
    size > 1 &&
    !entries[0].in_use &&
    ["Prev", "XRefStm", "Encrypt"].all(key => {
      trailer.lookup_immediate(pdf_name(key)) is None
    }) else {
    return None
  }
  for number, entry in entries {
    guard entry.object_number == number &&
      (!entry.in_use || (entry.offset > 0 && entry.offset < xref)) else {
      return None
    }
  }
  // Keep the validated table and all object offsets. Only the read view gets a new pointer.
  let repaired = Buffer(size_hint=bytes.length())
  repaired.write_bytes(bytes[:marker])
  repaired.write_bytes(@utf8.encode("startxref\n\{xref}\n%%EOF")[:])
  Some(@pdflite.pdf_read_classic_document_from_view(repaired.to_bytes()[:]))
}
