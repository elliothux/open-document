///|
fn pptx_connector_end(
  value : Json,
) -> @model.ConnectorEnd raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.keys().all(k => ["x", "y", "target", "site"].contains(k)) else {
    @failure.reject("invalid-operation", "Unknown connector endpoint fields")
  }
  {
    x: field_number(value, "x"),
    y: field_number(value, "y"),
    target: field_string(value, "target"),
    site: field_int(value, "site"),
  }
}

///|
fn pptx_connector_edit(
  value : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.keys().all(k => ["action", "kind", "start", "end"].contains(k)) &&
    fields.get("start") is Some(start) &&
    fields.get("end") is Some(end) else {
    @failure.reject("invalid-operation", "Connector endpoints are required")
  }
  if field_string(value, "action") == "insertConnector" {
    @model.InsertConnector(
      field_string(value, "kind"),
      pptx_connector_end(start),
      pptx_connector_end(end),
    )
  } else {
    @model.ConnectorEndpoints(
      field_string(value, "kind"),
      pptx_connector_end(start),
      pptx_connector_end(end),
    )
  }
}
