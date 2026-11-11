///|
pub fn abi_version() -> Int32 {
  @common.abi_version()
}

///|
pub fn call_wire(
  context : Context,
  input : String,
  first : String,
  second : String,
) -> String {
  call(context, input, first~, second~)
}
