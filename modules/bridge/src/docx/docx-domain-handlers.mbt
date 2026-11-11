///|
priv struct TrackingRequest {
  revision : @common.RequestInt
  author : @common.RequiredNullable[String]
  date : String
} derive(@json.FromJson)

///|
priv struct RevisionGeometryRequest {
  revisionId : String
} derive(@json.FromJson)

///|
let domain_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "docxMathFractions": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.math_fractions(revision)
  },
  "docxMathScripts": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.math_scripts(revision)
  },
  "docxMathExpressions": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.math_expressions(revision)
  },
  "editDocxMathFraction": (context, session, input) => {
    context.edit_math_command(session, "fraction", input)
  },
  "editDocxMathScript": (context, session, input) => {
    context.edit_math_command(session, "script", input)
  },
  "editDocxMath": (context, session, input) => {
    context.edit_math_command(session, "math", input)
  },
  "docxCharts": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.charts(revision)
  },
  "editDocxChart": (context, session, input) => {
    context.edit_chart_command(session, input)
  },
  "docxShapes": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.shapes(revision)
  },
  "editDocxShape": (context, session, input) => {
    context.edit_shape_command(session, input)
  },
  "docxInk": (context, session, input) => context.ink_operation(session, input),
  "docxPictures": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.pictures(revision)
  },
  "editDocxPicture": (context, session, input) => {
    context.edit_picture_command(session, input, false)
  },
  "docxDrawingGesture": (context, session, input) => {
    context.edit_picture_command(session, input, true)
  },
  "insertDocxTable": (context, session, input) => {
    context.docx_table(session, true, input)
  },
  "editDocxTable": (context, session, input) => {
    context.docx_table(session, false, input)
  },
  "docxTracking": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.tracking(revision)
  },
  "setDocxTracking": (_context, session, input) => {
    let command : TrackingRequest = @common.request(input)
    session.track_changes(
      command.revision.value,
      command.author.value,
      command.date,
    )
  },
  "docxRevisions": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.revisions(revision)
  },
  "docxRevisionGeometry": (context, session, input) => {
    let revision = @common.request_revision(input)
    let layout = context.current_layout(input)
    let geometry : RevisionGeometryRequest = @common.request(input)
    {
      "layoutId": context.layout_id,
      "revision": layout.revision,
      "rects": session.revision_rects(revision, layout, geometry.revisionId),
    }
  },
  "resolveDocxRevisions": (context, session, input) => {
    context.resolve_revision_command(session, input)
  },
}
