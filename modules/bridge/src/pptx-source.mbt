///|
fn pptx_source_edit(change : Json) -> @pptx.SlideEdit raise @failure.Failure {
  let action = field_string(change, "action")
  guard change is Object(fields) &&
    fields.length() == (if action == "sourceName" { 2 } else { 1 }) else {
    @failure.reject("invalid-operation", "Invalid source edit fields")
  }
  match action {
    "addLayout" => @pptx.AddLayout
    "copyLayout" => @pptx.CopyLayout
    "deleteLayout" => @pptx.DeleteLayout
    "deleteMaster" => @pptx.DeleteMaster
    "addMaster" => @pptx.AddMaster
    "copyMaster" => @pptx.CopyMaster
    "sourceName" => @pptx.SourceName(field_string(change, "name"))
    _ => @failure.reject("invalid-operation", "Unknown source edit")
  }
}
