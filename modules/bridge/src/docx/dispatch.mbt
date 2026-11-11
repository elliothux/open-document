///|
fn Context::dispatch(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Context session is closed")
  }
  let command : @common.OperationRequest = @common.request(request)
  let operation = command.operation
  if self.docx is Some(session) &&
    request is { "trackingDate": String(date), .. } {
    session.tracking_clock(date)
  }
  if lifecycle_handlers.get(operation) is Some(handler) {
    return handler(self, request)
  }
  if session_handlers.get(operation) is Some(handler) {
    guard self.docx is Some(session) else {
      @failure.reject("invalid-operation", "Open a DOCX session first")
    }
    return handler(self, session, request)
  }
  @failure.reject("invalid-operation", "Unknown foundation operation")
}
