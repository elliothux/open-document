///|
#derive(@json.FromJson)
priv struct AnnotationStyleRequest {
  placement : PlacementRequest
  color : String
  opacity : @common.RequestNumber
  border : @common.RequestNumber
  author : String
  text : String
}

///|
fn AnnotationStyleRequest::style(
  self : AnnotationStyleRequest,
) -> @model.PdfAnnotationStyle {
  {
    placement: self.placement.placement(),
    color: self.color,
    opacity: self.opacity.value,
    border: self.border.value,
    author: self.author,
    text: self.text,
  }
}

///|
priv struct PdfCoordinates {
  value : Array[Double]
}

///|
impl @json.FromJson for PdfCoordinates with fn from_json(input, path) {
  guard input is Array(points) &&
    points.length() <= @model.AnnotationCoordinates else {
    raise @json.JsonDecodeError((path, "Coordinates exceed budget"))
  }
  let value = points.map(point => {
    guard point is Number(coordinate, ..) &&
      !coordinate.is_nan() &&
      !coordinate.is_inf() else {
      raise @json.JsonDecodeError(
        (path, "Coordinates must be finite JSON numbers"),
      )
    }
    coordinate
  })
  { value, }
}

///|
priv struct PdfInkStrokes {
  value : Array[Array[Double]]
}

///|
impl @json.FromJson for PdfInkStrokes with fn from_json(input, path) {
  guard input is Array(strokes) &&
    !strokes.is_empty() &&
    strokes.length() <= @model.InkStrokeCount else {
    raise @json.JsonDecodeError((path, "Bounded ink strokes are required"))
  }
  let mut remaining = @model.AnnotationCoordinates
  for stroke in strokes {
    guard stroke is Array(points) && points.length() <= remaining else {
      raise @json.JsonDecodeError((path, "Ink coordinates exceed budget"))
    }
    remaining -= points.length()
  }
  let value = strokes.map(stroke => {
    let points : PdfCoordinates = @json.from_json(stroke, path~)
    points.value
  })
  { value, }
}

///|
#derive(@json.FromJson)
priv struct AnnotationRequest {
  revision : @common.RequestInt
  page : String
  annotation : String
}

///|
#derive(@json.FromJson)
priv struct EditAnnotationRequest {
  revision : @common.RequestInt
  page : String
  annotation : String
  style : AnnotationStyleRequest
}

///|
#derive(@json.FromJson)
priv struct ReplyAnnotationRequest {
  revision : @common.RequestInt
  page : String
  annotation : String
  text : String
  author : String
}

///|
#derive(@json.FromJson)
priv struct AnnotationTextRequest {
  revision : @common.RequestInt
  page : String
  annotation : String
  text : String
}

///|
#derive(@json.FromJson)
priv struct InkAnnotationRequest {
  revision : @common.RequestInt
  page : String
  style : AnnotationStyleRequest
  strokes : PdfInkStrokes
  signature : Bool
}

///|
#derive(@json.FromJson)
priv struct StampAnnotationRequest {
  bytes : String
  revision : @common.RequestInt
  page : String
  style : AnnotationStyleRequest
  pixelWidth : @common.RequestInt
  pixelHeight : @common.RequestInt
  signature : Bool
}

///|
#derive(@json.FromJson)
priv struct DrawingAnnotationSpec {
  kind : String
  placement : PlacementRequest
  points : PdfCoordinates
  color : String
  opacity : @common.RequestNumber
  border : @common.RequestNumber
  author : String
  text : String
  arrow : Bool
}

///|
#derive(@json.FromJson)
priv struct DrawingAnnotationRequest {
  revision : @common.RequestInt
  page : String
  spec : DrawingAnnotationSpec
}

///|
#derive(@json.FromJson)
priv struct MarkTextRequest {
  revision : @common.RequestInt
  layoutId : @common.RequestInt
  kind : String
}

///|
let annotation_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "pdfAnnotation": (_context, session, input) => {
    let command : AnnotationRequest = @common.request(input)
    let result = session.annotation_details(
      command.revision.value,
      command.page,
      command.annotation,
    )
    ToJson::to_json(result).stringify()
  },
  "pdfAnnotationThread": (_context, session, input) => {
    let command : AnnotationRequest = @common.request(input)
    let result = session.annotation_thread(
      command.revision.value,
      command.page,
      command.annotation,
    )
    ToJson::to_json(result).stringify()
  },
  "editPdfAnnotation": (_context, session, input) => {
    let command : EditAnnotationRequest = @common.request(input)
    session
    .edit_annotation(
      command.revision.value,
      command.page,
      command.annotation,
      command.style.style(),
    )
    .stringify()
  },
  "replyPdfAnnotation": (_context, session, input) => {
    let command : ReplyAnnotationRequest = @common.request(input)
    session
    .reply_annotation(
      command.revision.value,
      command.page,
      command.annotation,
      command.text,
      command.author,
    )
    .stringify()
  },
  "deletePdfAnnotationThread": (_context, session, input) => {
    let command : AnnotationRequest = @common.request(input)
    session
    .delete_annotation_thread(
      command.revision.value,
      command.page,
      command.annotation,
    )
    .stringify()
  },
  "updatePdfAnnotation": (_context, session, input) => {
    let command : AnnotationTextRequest = @common.request(input)
    session
    .change_annotation(
      command.revision.value,
      command.page,
      command.annotation,
      command.text,
      false,
    )
    .stringify()
  },
  "deletePdfAnnotation": (_context, session, input) => {
    let command : AnnotationRequest = @common.request(input)
    session
    .change_annotation(
      command.revision.value,
      command.page,
      command.annotation,
      "",
      true,
    )
    .stringify()
  },
  "addPdfInkAnnotation": (_context, session, input) => {
    let command : InkAnnotationRequest = @common.request(input)
    let style = command.style.style()
    session
    .add_drawing_annotation(
      command.revision.value,
      command.page,
      {
        kind: "Ink",
        placement: style.placement,
        points: [],
        color: style.color,
        opacity: style.opacity,
        border: style.border,
        author: style.author,
        text: style.text,
        arrow: false,
      },
      strokes=command.strokes.value,
      signature=command.signature,
    )
    .stringify()
  },
  "addPdfStampAnnotation": (_context, session, input) => {
    let command : StampAnnotationRequest = @common.request(input)
    session
    .add_stamp_annotation(
      command.revision.value,
      command.page,
      command.style.style(),
      command.pixelWidth.value,
      command.pixelHeight.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
      command.signature,
    )
    .stringify()
  },
  "addPdfDrawingAnnotation": (_context, session, input) => {
    let command : DrawingAnnotationRequest = @common.request(input)
    let spec = command.spec
    session
    .add_drawing_annotation(command.revision.value, command.page, {
      kind: spec.kind,
      placement: spec.placement.placement(),
      points: spec.points.value,
      color: spec.color,
      opacity: spec.opacity.value,
      border: spec.border.value,
      author: spec.author,
      text: spec.text,
      arrow: spec.arrow,
    })
    .stringify()
  },
  "markPdfText": (_context, session, input) => {
    let command : MarkTextRequest = @common.request(input)
    session
    .add_highlight(
      command.revision.value,
      command.layoutId.value,
      kind=command.kind,
    )
    .stringify()
  },
}
