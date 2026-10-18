///|
fn Foundation::docx_ruler(
  self : Foundation,
  session : @docx.Session,
  request : Json,
  edit : Bool,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  guard self.layout is Some(layout) else {
    @failure.reject("stale-layout", "Ruler requires a displayed layout")
  }
  if !edit {
    let result = session.ruler(revision, layout)
    guard result is Object(fields) else { abort("Expected ruler result") }
    fields["layoutId"] = Json(self.layout_id)
    return result
  }
  ignore(self.current_layout(request))
  guard request is { "change": Object(fields) as change, .. } else {
    @failure.reject("invalid-operation", "Ruler change is required")
  }
  let kind = field_string(change, "kind")
  let allowed = if kind == "tab" {
    ["kind", "position", "snap", "index", "align", "remove"]
  } else {
    ["kind", "position", "snap"]
  }
  guard fields.length() == allowed.length() &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid ruler change fields")
  }
  let position = xlsx_number(change, "position")
  let snap = xlsx_boolean(change, "snap")
  let change = match kind {
    "first" | "hanging" | "left" | "right" =>
      @docx.RulerIndent(kind, position, snap)
    "marginLeft" | "marginRight" => @docx.RulerMargin(kind, position, snap)
    "tab" => {
      let index = xlsx_number(change, "index")
      guard index >= -1 && index <= 63 && index == index.to_int().to_double() else {
        @failure.reject("invalid-operation", "Invalid ruler tab index")
      }
      @docx.RulerTab(
        index.to_int(),
        position,
        field_string(change, "align"),
        xlsx_boolean(change, "remove"),
        snap,
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown ruler marker")
  }
  let result = session.edit_ruler(
    revision,
    layout,
    field_selection(request),
    change,
  )
  self.layout = None
  result
}
