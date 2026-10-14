///|
fn font_input_bytes(input : String) -> Bytes raise @failure.Failure {
  guard input.length() <= 33554432 else {
    @failure.reject("limit-exceeded", "Font input exceeds budget")
  }
  Bytes::makei(input.length(), i => {
    let value = input[i].to_int()
    guard value <= 255 else {
      @failure.reject("invalid-operation", "Invalid byte input")
    }
    value.to_byte()
  })
}

///|
pub fn foundation_add_font(
  context : Foundation,
  input : String,
  identity : String,
) -> String {
  foundation_response(() => {
    guard !context.closed else {
      @failure.reject("closed-session", "Foundation session is closed")
    }
    let index = context.probe.add_font(font_input_bytes(input), identity)
    context.layout = None
    { "font": index }
  })
}
