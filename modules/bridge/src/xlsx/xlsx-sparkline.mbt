///|
#derive(@json.FromJson)
priv struct SparklineRequest {
  cell : String
  source : @common.RequiredNullable[String]
  kind : String
}

///|
fn xlsx_sparkline_edit(
  change : Json,
) -> @model.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 4 &&
    fields.contains("action") else {
    @failure.reject("invalid-operation", "Invalid sparkline command")
  }
  let request : SparklineRequest = @common.request(change)
  @model.Sparkline(request.cell, request.source.value, request.kind)
}
