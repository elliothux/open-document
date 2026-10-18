///|
fn foundation_response(operation : () -> Json raise @failure.Failure) -> String {
  let result : Json = { "ok": true, "value": operation() } catch {
    @failure.Failure(code~, part~, offset~, message~) =>
      {
        "ok": false,
        "error": {
          "code": code,
          "part": part,
          "offset": offset,
          "message": message,
        },
      }
  }
  result.stringify()
}

///|
pub fn foundation_call(context : Foundation, input : String) -> String {
  foundation_response(() => {
    guard input.length() <= 100000000 else {
      @failure.reject("limit-exceeded", "ABI input exceeds budget")
    }
    let request = @json.parse(input) catch {
      _ => @failure.reject("invalid-operation", "Invalid request JSON")
    }
    context.dispatch(request)
  })
}
