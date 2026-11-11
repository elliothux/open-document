///|
#derive(@json.FromJson)
priv struct RulerChangeRequest {
  kind : String
  position : @common.RequestNumber
  snap : Bool
}

///|
#derive(@json.FromJson)
priv struct RulerTabRequest {
  index : @common.RequestNumber
  align : String
  remove : Bool
}

///|
fn Context::docx_ruler(
  self : Context,
  session : @model.Session,
  request : Json,
  edit : Bool,
) -> Json raise @failure.Failure {
  let revision = @common.request_revision(request)
  guard self.layout is Some(layout) else {
    @failure.reject("stale-layout", "Ruler requires a displayed layout")
  }
  if !edit {
    return Json(session.ruler(revision, layout, self.layout_id))
  }
  ignore(self.current_layout(request))
  let change = ruler_change(request)
  let result = session.edit_ruler(
    revision,
    layout,
    field_selection(request),
    change,
  )
  self.layout = None
  result
}

///|
fn ruler_change(request : Json) -> @model.RulerEdit raise @failure.Failure {
  guard request is { "change": Object(fields) as change, .. } else {
    @failure.reject("invalid-operation", "Ruler change is required")
  }
  let command : RulerChangeRequest = @common.request(change)
  let kind = command.kind
  let allowed = if kind == "tab" {
    ["kind", "position", "snap", "index", "align", "remove"]
  } else {
    ["kind", "position", "snap"]
  }
  guard fields.length() == allowed.length() &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid ruler change fields")
  }
  let position = command.position.value
  let snap = command.snap
  match kind {
    "first" | "hanging" | "left" | "right" =>
      @model.RulerIndent(kind, position, snap)
    "marginLeft" | "marginRight" => @model.RulerMargin(kind, position, snap)
    "tab" => {
      let tab : RulerTabRequest = @common.request(change)
      let index = tab.index.value
      guard index >= -1 &&
        index < @layout.TabStopCount.to_double() &&
        index == index.to_int().to_double() else {
        @failure.reject("invalid-operation", "Invalid ruler tab index")
      }
      @model.RulerTab(index.to_int(), position, tab.align, tab.remove, snap)
    }
    _ => @failure.reject("invalid-operation", "Unknown ruler marker")
  }
}
