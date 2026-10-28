///|
priv struct PdfSourceSegment {
  index : Int32
  number : Int32
  start : Int32
  end : Int32
  owned : Bool
}

///|
priv struct PdfFormCall {
  number : Int32
  start : Int32
  end : Int32
  resources : @syntax.PdfObject
  child : Int32
  clip : @layout.Matrix
}

///|
priv struct PdfSourceOrigin {
  segments : Array[PdfSourceSegment]
  number : Int32
  rootIndex : Int32
  path : Array[PdfFormCall]
  owned : Bool
}

///|
priv struct PdfSourceLocation {
  number : Int32
  rootIndex : Int32
  start : Int32
  end : Int32
  resources : @syntax.PdfObject
  path : Array[PdfFormCall]
  owned : Bool
}

///|
priv struct PdfSourceObject {
  id : String
  kind : String
  location : PdfSourceLocation?
  reference : @syntax.PdfObject
  matrix : @layout.Matrix
  before : @pdflite.PdfContentTextState
  after : @pdflite.PdfContentTextState
  spans : Array[TextSpan]
  font : String
  fontIndex : Int32?
  color : String
  reason : String
  op : @content.PdfContentOp
}

///|
fn pdf_operator_ranges(
  bytes : Bytes,
  count : Int32,
) -> Array[(Int32, Int32)] raise {
  let cursor = @pdfcore.byte_cursor_of_view(bytes)
  let ranges : Array[(Int32, Int32)] = []
  let mut start : Int32? = None
  let mut depth = 0
  while cursor.position() < bytes.length() {
    @syntax.pdf_cursor_drop_whitespace(cursor)
    if cursor.position() >= bytes.length() {
      break
    }
    let before = cursor.position()
    if cursor.peek_byte() == 37 {
      ignore(@syntax.pdf_cursor_lex_comment(cursor))
      continue
    }
    if start is None {
      start = Some(before)
    }
    let first = cursor.peek_byte()
    if [40, 47, 60, 62, 91, 93].contains(first) ||
      @syntax.pdf_is_number_start_byte(first) {
      let lexeme = @syntax.pdf_cursor_lex_token(cursor)
      match lexeme {
        LexLeftSquare | LexLeftDict => depth += 1
        LexRightSquare | LexRightDict => depth -= 1
        _ => ()
      }
      guard depth >= 0 && depth <= 64 else {
        @failure.reject(
          "protected-content", "PDF operand boundaries are unsupported",
        )
      }
    } else {
      let token = @syntax.pdf_cursor_read_regular_token_view(cursor)
      let keyword = @utf8.decode_lossy(token.to_owned())
      if !["true", "false", "null"].contains(keyword) {
        guard depth == 0 && keyword != "BI" && !keyword.is_empty() else {
          @failure.reject(
            "protected-content", "PDF inline or nested operator boundaries are protected",
          )
        }
        ranges.push((start.unwrap(), cursor.position()))
        start = None
      }
    }
    guard cursor.position() > before else {
      @failure.reject("protected-content", "PDF source token did not advance")
    }
  }
  guard start is None && depth == 0 && ranges.length() == count else {
    @failure.reject(
      "protected-content", "PDF source ranges do not match parsed operators",
    )
  }
  ranges
}

///|
fn page_source(
  document : @pdflite.PdfDocument,
  contents : @syntax.PdfObject,
) -> (Bytes, PdfSourceOrigin) raise {
  let resolved = resolve(document, contents)
  let array = resolved is PdfArray(_)
  let references = match resolved {
    PdfArray(items) => items
    PdfNull => []
    _ => [contents]
  }
  let output : Array[Byte] = []
  let segments : Array[PdfSourceSegment] = []
  for index, reference in references {
    let bytes = stream_bytes(document, reference)
    guard bytes.length() < 16777216 - output.length() else {
      @failure.reject(
        "limit-exceeded", "PDF content exceeds source-location budget",
      )
    }
    let object = resolve(document, reference)
    let owned = match object {
      PdfStreamObject(s) => raw(s.dictionary, "ODIdentity") != @syntax.PdfNull
      _ => false
    }
    segments.push({
      index,
      number: match reference {
        PdfIndirect(number) => number
        _ => 0
      },
      start: output.length(),
      end: output.length() + bytes.length(),
      owned,
    })
    for byte in bytes {
      output.push(byte)
    }
    if array {
      output.push(10)
    }
  }
  (
    Bytes::from_array(output),
    { segments, number: 0, rootIndex: 0, path: [], owned: false, },
  )
}

///|
fn source_location(
  origin : PdfSourceOrigin?,
  ranges : Array[(Int32, Int32)]?,
  index : Int32,
  resources : @syntax.PdfObject,
) -> PdfSourceLocation? {
  guard origin is Some(origin) &&
    ranges is Some(ranges) &&
    index < ranges.length() else {
    return None
  }
  let (start, end) = ranges[index]
  if origin.number > 0 {
    return Some({
      number: origin.number,
      rootIndex: origin.rootIndex,
      start,
      end,
      resources,
      path: origin.path,
      owned: origin.owned,
    })
  }
  for segment in origin.segments {
    if segment.number > 0 && start >= segment.start && end <= segment.end {
      return Some({
        number: segment.number,
        rootIndex: segment.index,
        start: start - segment.start,
        end: end - segment.start,
        resources,
        path: origin.path,
        owned: segment.owned,
      })
    }
  }
  None
}

///|
fn source_identity(
  page : String,
  revision : Int32,
  location : PdfSourceLocation?,
  identity : String,
  index : Int32,
) -> String {
  let scope = match location {
    Some(location) =>
      "\{location.rootIndex}/" +
      location.path.map(call => "\{call.number}:\{call.start}").join("/")
    None => identity
  }
  "\{page}/r\{revision}/source/\{scope}/op\{index}"
}
