///|
priv struct SelectionViewRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  formatTable : Bool
  describeText : Bool
} derive(@json.FromJson)

///|
priv struct SelectionGeometryResponse {
  layoutId : Int32
  revision : Int32
  rects : Array[@layout.SelectionRect]
} derive(ToJson)

///|
priv struct SelectionViewResponse {
  layoutId : Int32
  revision : Int32
  caret : HitResponse
  geometry : SelectionGeometryResponse
  formatting : Json
  selectedText : String
  selectionError : String
} derive(ToJson)

///|
fn Context::selection_caret(
  self : Context,
  session : @model.Session,
  layout : @layout.Layout,
  position : @model.Position,
) -> HitResponse raise @failure.Failure {
  session.check_position(position)
  self.hit_result(
    session,
    layout.caret(
      position.paragraph,
      position.offset,
      position.affinity,
      bidi_level?=position.bidiLevel,
      frame_start?=position.frameStart,
    ),
  )
}

///|
fn Context::selection_geometry(
  self : Context,
  session : @model.Session,
  layout : @layout.Layout,
  selection : @model.Selection,
) -> SelectionGeometryResponse raise @failure.Failure {
  session.check_position(selection.anchor)
  session.check_position(selection.focus)
  {
    layoutId: self.layout_id,
    revision: layout.revision,
    rects: session.selection_rects(layout, selection),
  }
}

///|
fn Context::selection_view(
  self : Context,
  session : @model.Session,
  layout : @layout.Layout,
  revision : Int32,
  selection : @model.Selection,
  format_table : Bool,
  describe_text : Bool,
  cached_formatting? : @model.FormattingQuery,
) -> Json raise @failure.Failure {
  guard layout.revision == revision else {
    @failure.reject(
      "stale-layout", "Selection view requires the current layout revision",
    )
  }
  let caret = self.selection_caret(session, layout, selection.focus)
  let geometry = self.selection_geometry(session, layout, selection)
  let formatting = if cached_formatting is Some(formatting) {
    Some(session.formatting_on_layout(formatting, layout))
  } else if format_table {
    Some(session.formatting_query(revision, selection, layout~))
  } else {
    None
  }
  let (text, reason) = if describe_text &&
    !(formatting is Some(format) && format.has_table_cells()) &&
    (
      selection.anchor.paragraph != selection.focus.paragraph ||
      selection.anchor.offset != selection.focus.offset
    ) {
    (session.selected_text(revision, selection, layout~), "") catch {
      @failure.Failure(
        code="protected-content"
        | "limit-exceeded",
        message~,
        ..
      ) => ("", message)
      error => raise error
    }
  } else {
    ("", "")
  }
  let result : SelectionViewResponse = {
    layoutId: self.layout_id,
    revision,
    caret,
    geometry,
    formatting: formatting.map(format => Json(format)).unwrap_or(Json::null()),
    selectedText: text,
    selectionError: reason,
  }
  ToJson::to_json(result)
}
