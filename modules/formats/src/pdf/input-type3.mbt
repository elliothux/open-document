///|
fn draw_type3_glyph(
  context : ContentContext,
  data : @pdflite.PdfType3Glyphs,
  code : Int32,
  name : String,
  transform : @layout.Matrix,
  state : GraphicsState,
  resources : @syntax.PdfObject,
  source : String,
  depth : Int32,
  uncolored : Bool,
) -> Unit raise {
  let document = context.session.document
  let mut procedure = @syntax.PdfNull
  for (key, value) in data.charprocs {
    @pdfcore.sdk_check(1)
    if key == pdf_name(name) {
      procedure = value
      break
    }
  }
  guard procedure != @syntax.PdfNull else {
    @failure.reject("invalid-pdf", "Missing Type 3 glyph procedure")
  }
  let own = resolve(document, data.resources)
  context.scope(@layout.Transform(@layout.Matrix::identity()))
  // Glyph programs paint the encoded glyph; their internal text is not page text.
  let child : ContentContext = {
    ..context,
    extraction: None,
    sources: [],
    collectSource: false,
    spans: [],
    chunks: [],
    units: 0,
    textComplete: true,
    displayComplete: true,
    marked: [],
  }
  interpret(
    child,
    stream_bytes(document, procedure),
    if own == @syntax.PdfDictionary([]) {
      resources
    } else {
      own
    },
    "\{source}/type3:\{code}",
    { ..state, matrix: transform.then(matrix(data.fontmatrix)), clips: 0, },
    depth + 1,
    type3=true,
    uncolored~,
  )
  context.restore()
  if !child.displayComplete {
    context.displayComplete = false
  }
}
