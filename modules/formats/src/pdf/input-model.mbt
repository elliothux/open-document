///|
pub(all) struct PdfBudget {
  fileBytes : Int
  objects : Int
  objectNumber : Int
  pages : Int
  revisions : Int
  depth : Int
  streamBytes : Int
  decodedBytes : Int
  steps : Int
  outputBytes : Int
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
  number : Int
  generation : Int
  id : String
  resources : @syntax.PdfObject
  media : @syntax.PdfObject
  crop : @syntax.PdfObject
  rotate : Int
  unit : Double
  width : Double
  height : Double
  matrix : @layout.Matrix
}

///|
struct TextSpan {
  start : Int
  end : Int
  text : String
  quad : Array[Double]
  source : String
  mapped : Bool
  invisible : Bool
} derive(ToJson)

///|
pub extend TextSpan with ToJson::{to_json}

///|
struct PageDisplay {
  page : String
  id : Int
  revision : Int
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
  width : Int
  height : Int
  decode : Array[Double]
  alpha : Bytes?
}

///|
priv struct ObjectChange {
  number : Int
  generation : Int
  before : @syntax.PdfObject?
  after : @syntax.PdfObject
}

///|
struct PdfHistory {
  changes : Array[ObjectChange]
  bytes : Int
  beforePage : String
  afterPage : String
  beforeSelection : (Int, Int)
  beforeState : Int
  afterState : Int
}

///|
pub struct PdfSession {
  document : @pdflite.PdfDocument
  mut original : Bytes
  budget : PdfBudget
  generations : Map[Int, Int]
  mut pages : Array[SourcePage]
  mut revision : Int
  mut layoutId : Int
  mut display : PageDisplay?
  mut current : String
  mut selection : (Int, Int)
  mut nextObject : Int
  mut stateId : Int
  mut nextState : Int
  undo : Array[PdfHistory]
  redo : Array[PdfHistory]
  mut historyBytes : Int
  readOnlyReason : String
  mut closed : Bool
}

///|
let pdf_layout_serial : Ref[Int] = Ref(0)

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
  revision : Int,
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
  if self.display is Some(display) {
    display.probe.close()
  }
  self.display = None
  self.document.sdk_clear()
  self.generations.clear()
  self.historyBytes = 0
}
