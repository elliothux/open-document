///|
pub(all) struct PdfBudget {
  fileBytes : Int32
  objects : Int32
  objectNumber : Int32
  pages : Int32
  revisions : Int32
  depth : Int32
  streamBytes : Int32
  decodedBytes : Int32
  steps : Int32
  outputBytes : Int32
} derive(ToJson)

///|
pub extend PdfBudget with ToJson::{to_json}

///|
pub fn PdfBudget::default() -> PdfBudget {
  {
    fileBytes: 67108864,
    objects: 100000,
    objectNumber: 1000000,
    pages: 1024,
    revisions: 128,
    depth: 64,
    streamBytes: 16777216,
    decodedBytes: 67108864,
    steps: 10000000,
    outputBytes: 67108864,
  }
}

///|
struct SourcePage {
  number : Int32
  generation : Int32
  id : String
  resources : @syntax.PdfObject
  media : @syntax.PdfObject
  crop : @syntax.PdfObject
  rotate : Int32
  unit : Double
  width : Double
  height : Double
  matrix : @layout.Matrix
}

///|
priv struct TextSpan {
  start : Int32
  end : Int32
  text : String
  quad : Array[Double]
  source : String
  mapped : Bool
  invisible : Bool
  cropVisible : Bool
}

///|
impl ToJson for TextSpan with fn to_json(self) {
  {
    "start": self.start,
    "end": self.end,
    "text": self.text,
    "quad": self.quad,
    "source": self.source,
    "mapped": self.mapped,
    "invisible": self.invisible,
  }
}

///|
struct PageDisplay {
  extraction : PdfExtractionData?
  sources : Array[PdfSourceObject]
  profile : Map[String, String]
  resources : @layout.Images
  imageBytes : Int32
  page : String
  id : Int32
  revision : Int32
  region : @layout.DrawingRegion
  text : String
  spans : Array[TextSpan]
  textComplete : Bool
  displayComplete : Bool
  diagnostics : Array[String]
  images : Array[String]
  jpeg : Map[String, JpegImage]
  probe : @layout.TextProbe
}

///|
priv struct JpegImage {
  bytes : Bytes
  width : Int32
  height : Int32
  decode : Array[Double]
  alpha : Bytes?
  matte : Array[Double]?
}

///|
priv struct ObjectChange {
  number : Int32
  generation : Int32
  before : @syntax.PdfObject?
  after : @syntax.PdfObject
}

///|
struct PdfHistory {
  beforeTrailer : @syntax.PdfObject
  afterTrailer : @syntax.PdfObject
  changes : Array[ObjectChange]
  bytes : Int32
  beforePage : String
  afterPage : String
  beforeSelection : (Int32, Int32)
  beforeState : Int32
  afterState : Int32
}

///|
pub struct PdfSession {
  document : @pdflite.PdfDocument
  mut original : Bytes
  budget : PdfBudget
  generations : Map[Int32, Int32]
  mut pages : Array[SourcePage]
  mut revision : Int32
  mut layoutId : Int32
  mut display : PageDisplay?
  views : Map[Int32, PageDisplay]
  mut current : String
  mut selection : (Int32, Int32)
  mut textRange : (String, Int32, String, Int32)?
  mut nextObject : Int32
  mut stateId : Int32
  mut nextState : Int32
  undo : Array[PdfHistory]
  redo : Array[PdfHistory]
  mut historyBytes : Int32
  readOnlyReason : String
  mut closed : Bool
}

///|
let pdf_layout_serial : Ref[Int32] = Ref(0)

///|
fn[T] pdf_bound(
  budget : PdfBudget,
  operation : () -> T raise,
) -> T raise @failure.Failure {
  let owner = !@pdfcore.sdk_active()
  if owner {
    @pdfcore.sdk_begin(
      budget.streamBytes,
      budget.decodedBytes,
      budget.steps,
      budget.depth,
      budget.objects,
      budget.objectNumber,
      budget.revisions,
    )
  }
  let result = operation() catch {
    error => {
      let exceeded = if owner {
        @pdfcore.sdk_end()
      } else {
        @pdfcore.sdk_exhausted()
      }
      if exceeded {
        @failure.reject("limit-exceeded", "PDF operation budget exceeded")
      }
      match error {
        @failure.Failure(..) as failure => raise failure
        @pdfcore.PdfError::FlateOutputLimitExceeded(_) =>
          @failure.reject("limit-exceeded", "PDF decoded stream exceeds budget")
        _ => @failure.reject("invalid-pdf", "PDF operation failed")
      }
    }
  }
  guard !(if owner { @pdfcore.sdk_end() } else { @pdfcore.sdk_exhausted() }) else {
    @failure.reject("limit-exceeded", "PDF operation budget exceeded")
  }
  result
}

///|
fn PdfSession::check(
  self : PdfSession,
  revision : Int32,
) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "PDF session is closed")
  }
  guard revision == self.revision else {
    @failure.reject("stale-revision", "PDF revision changed")
  }
}

///|
pub fn PdfSession::close(self : PdfSession) -> Unit {
  self.closed = true
  self.original = b""
  self.pages = []
  self.undo.clear()
  self.redo.clear()
  for _, display in self.views {
    display.probe.close()
  }
  self.views.clear()
  self.display = None
  self.document.sdk_clear()
  self.generations.clear()
  self.historyBytes = 0
}
