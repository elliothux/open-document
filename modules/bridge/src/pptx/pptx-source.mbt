///|
fn pptx_source_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  let action = field_string(change, "action")
  guard change is Object(fields) &&
    fields.length() == (if action == "sourceName" { 2 } else { 1 }) else {
    @failure.reject("invalid-operation", "Invalid source edit fields")
  }
  match action {
    "addLayout" => @model.AddLayout
    "copyLayout" => @model.CopyLayout
    "deleteLayout" => @model.DeleteLayout
    "deleteMaster" => @model.DeleteMaster
    "addMaster" => @model.AddMaster
    "copyMaster" => @model.CopyMaster
    "sourceName" => @model.SourceName(field_string(change, "name"))
    _ => @failure.reject("invalid-operation", "Unknown source edit")
  }
}
