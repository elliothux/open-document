///|
fn pptx_source_edit(
  action : String,
  change : Json,
) -> @model.SlideEdit raise @failure.Failure {
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
    "sourceName" => {
      let request : NameRequest = @common.request(change)
      @model.SourceName(request.name)
    }
    _ => @failure.reject("invalid-operation", "Unknown source edit")
  }
}
