///|
#derive(@json.FromJson)
priv struct ConnectorEndRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
  target : String
  site : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct ConnectorEditRequest {
  kind : String
  start : ConnectorEndRequest
  end : ConnectorEndRequest
}

///|
fn ConnectorEndRequest::endpoint(
  self : ConnectorEndRequest,
) -> @model.ConnectorEnd {
  {
    x: self.x.value,
    y: self.y.value,
    target: self.target,
    site: self.site.value,
  }
}

///|
fn pptx_connector_edit(
  action : String,
  value : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  guard value is Object(fields) && fields.length() == 4 else {
    @failure.reject("invalid-operation", "Connector endpoints are required")
  }
  guard fields.get("start") is Some(Object(start)) &&
    fields.get("end") is Some(Object(end)) &&
    start.length() == 4 &&
    end.length() == 4 else {
    @failure.reject("invalid-operation", "Unknown connector endpoint fields")
  }
  let request : ConnectorEditRequest = @common.request(value)
  let start = request.start.endpoint()
  let end = request.end.endpoint()
  if action == "insertConnector" {
    @model.InsertConnector(request.kind, start, end)
  } else {
    @model.ConnectorEndpoints(request.kind, start, end)
  }
}
