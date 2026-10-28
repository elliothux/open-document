///|
fn pdf_annotation_style(
  value : Json,
) -> @model.PdfAnnotationStyle raise @failure.Failure {
  guard value is { "placement": placement, .. } else {
    @failure.reject("invalid-operation", "Annotation placement is required")
  }
  {
    placement: pdf_placement(placement),
    color: field_string(value, "color"),
    opacity: field_number(value, "opacity"),
    border: field_number(value, "border"),
    author: field_string(value, "author"),
    text: field_string(value, "text"),
  }
}

///|
fn Context::pdf_annotation_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  let revision = field_int(request, "revision")
  let page = field_string(request, "page")
  match operation {
    "pdfAnnotation" =>
      session.annotation_details(
        revision,
        page,
        field_string(request, "annotation"),
      )
    "pdfAnnotationThread" =>
      session.annotation_thread(
        revision,
        page,
        field_string(request, "annotation"),
      )
    "editPdfAnnotation" => {
      guard request is { "style": style, .. } else {
        @failure.reject("invalid-operation", "Annotation style is required")
      }
      session.edit_annotation(
        revision,
        page,
        field_string(request, "annotation"),
        pdf_annotation_style(style),
      )
    }
    "replyPdfAnnotation" =>
      session.reply_annotation(
        revision,
        page,
        field_string(request, "annotation"),
        field_string(request, "text"),
        field_string(request, "author"),
      )
    "deletePdfAnnotationThread" =>
      session.delete_annotation_thread(
        revision,
        page,
        field_string(request, "annotation"),
      )
    "addPdfInkAnnotation" => {
      guard request is { "style": style, "strokes": Array(strokes), .. } &&
        !strokes.is_empty() &&
        strokes.length() <= 4096 else {
        @failure.reject("invalid-operation", "Bounded ink strokes are required")
      }
      let style = pdf_annotation_style(style)
      let strokes = strokes.map(stroke => {
        guard stroke is Array(points) && points.length() <= 32768 else {
          @failure.reject(
            "invalid-operation", "Ink stroke coordinates exceed budget",
          )
        }
        points.map(point => {
          guard point is Number(value, ..) && !value.is_nan() && !value.is_inf() else {
            @failure.reject(
              "invalid-operation", "Ink coordinates must be finite numbers",
            )
          }
          value
        })
      })
      session.add_drawing_annotation(
        revision,
        page,
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
        strokes~,
        signature=field_boolean(request, "signature"),
      )
    }
    "addPdfStampAnnotation" => {
      guard request is { "style": style, .. } else {
        @failure.reject("invalid-operation", "Stamp style is required")
      }
      session.add_stamp_annotation(
        revision,
        page,
        pdf_annotation_style(style),
        field_int(request, "pixelWidth"),
        field_int(request, "pixelHeight"),
        input_bytes(request, 16777216),
        field_boolean(request, "signature"),
      )
    }
    _ =>
      @failure.reject("invalid-operation", "Unknown PDF annotation operation")
  }
}
