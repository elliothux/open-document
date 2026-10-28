///|
pub fn abi_version() -> Int {
  1
}

///|
pub fn docx_new() -> @docx.Context {
  @docx.new_context()
}

///|
pub fn docx_call(context : @docx.Context, input : String) -> String {
  @docx.call(context, input)
}

///|
pub fn docx_add_font(
  context : @docx.Context,
  input : String,
  identity : String,
) -> String {
  @docx.add_font(context, input, identity)
}

///|
pub fn docx_close(context : @docx.Context) -> Unit {
  @docx.close(context)
}

///|
pub fn xlsx_new() -> @xlsx.Context {
  @xlsx.new_context()
}

///|
pub fn xlsx_call(context : @xlsx.Context, input : String) -> String {
  @xlsx.call(context, input)
}

///|
pub fn xlsx_add_font(
  context : @xlsx.Context,
  input : String,
  identity : String,
) -> String {
  @xlsx.add_font(context, input, identity)
}

///|
pub fn xlsx_close(context : @xlsx.Context) -> Unit {
  @xlsx.close(context)
}

///|
pub fn pptx_new() -> @pptx.Context {
  @pptx.new_context()
}

///|
pub fn pptx_call(context : @pptx.Context, input : String) -> String {
  @pptx.call(context, input)
}

///|
pub fn pptx_add_font(
  context : @pptx.Context,
  input : String,
  identity : String,
) -> String {
  @pptx.add_font(context, input, identity)
}

///|
pub fn pptx_close(context : @pptx.Context) -> Unit {
  @pptx.close(context)
}

///|
pub fn pdf_new() -> @pdf.Context {
  @pdf.new_context()
}

///|
pub fn pdf_call(context : @pdf.Context, input : String) -> String {
  @pdf.call(context, input)
}

///|
pub fn pdf_add_font(
  context : @pdf.Context,
  input : String,
  identity : String,
) -> String {
  @pdf.add_font(context, input, identity)
}

///|
pub fn pdf_close(context : @pdf.Context) -> Unit {
  @pdf.close(context)
}
