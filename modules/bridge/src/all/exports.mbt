///|
pub fn abi_version() -> Int32 {
  @common.abi_version()
}

///|
pub fn docx_new() -> @docx.Context {
  @docx.new_context()
}

///|
pub fn docx_call(
  context : @docx.Context,
  input : String,
  first : String,
  second : String,
) -> String {
  @docx.call_wire(context, input, first, second)
}

///|
pub fn docx_output(context : @docx.Context, slot : Int32) -> String? {
  @docx.take_output(context, slot)
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
pub fn xlsx_call(
  context : @xlsx.Context,
  input : String,
  first : String,
  second : String,
) -> String {
  @xlsx.call_wire(context, input, first, second)
}

///|
pub fn xlsx_output(context : @xlsx.Context, slot : Int32) -> String? {
  @xlsx.take_output(context, slot)
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
pub fn pptx_call(
  context : @pptx.Context,
  input : String,
  first : String,
  second : String,
) -> String {
  @pptx.call_wire(context, input, first, second)
}

///|
pub fn pptx_output(context : @pptx.Context, slot : Int32) -> String? {
  @pptx.take_output(context, slot)
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
pub fn pdf_call(
  context : @pdf.Context,
  input : String,
  first : String,
  second : String,
) -> String {
  @pdf.call_wire(context, input, first, second)
}

///|
pub fn pdf_output(context : @pdf.Context, slot : Int32) -> String? {
  @pdf.take_output(context, slot)
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
