///|
fn ShapeSettings::checked(
  self : ShapeSettings,
  dimensions : Dimensions,
) -> SheetShape raise @failure.Failure {
  check_picture_text(self.name, self.description)
  guard ["rect", "ellipse", "line", "textBox"].contains(self.kind) &&
    ["fixed", "move", "size"].contains(self.anchor) &&
    [self.rect.x, self.rect.y, self.rect.width, self.rect.height].all(v => {
      !v.is_nan() && !v.is_inf() && v >= 0
    }) &&
    self.rect.width <= 14400 &&
    self.rect.height <= 14400 &&
    (if self.kind == "line" {
      self.rect.width >= 0.1 || self.rect.height >= 0.1
    } else {
      self.rect.width >= 0.1 && self.rect.height >= 0.1
    }) &&
    self.rect.x + self.rect.width <= dimensions.columns.position(16385) &&
    self.rect.y + self.rect.height <= dimensions.rows.position(1048577) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet shape kind position or dimensions",
    )
  }
  guard self.insets.length() == 4 &&
    self.text.length() <= 32767 &&
    @xml.valid_text(self.text) &&
    !self.font.trim().is_empty() &&
    self.font.length() <= 255 &&
    @xml.valid_text(self.font) &&
    !self.size.is_nan() &&
    !self.size.is_inf() &&
    self.size >= 1 &&
    self.size <= 400 &&
    !self.line_width.is_nan() &&
    !self.line_width.is_inf() &&
    self.line_width >= 0 &&
    self.line_width <= 1000 &&
    self.insets.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400) &&
    ["left", "center", "right"].contains(self.align) &&
    ["top", "center", "bottom"].contains(self.vertical) &&
    (self.kind != "line" || self.text.is_empty()) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet shape text or appearance",
    )
  }
  let fill = self.fill.map(color_hex).unwrap_or("")
  let stroke = self.stroke.map(color_hex).unwrap_or("")
  {
    preset: if self.kind == "textBox" {
      "rect"
    } else {
      self.kind
    },
    text_box: self.kind == "textBox",
    fill,
    stroke,
    line_width: (self.line_width * 12700).round() / 12700,
    text: self.text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n"),
    font: self.font,
    bold: self.bold,
    italic: self.italic,
    size: (self.size * 100).round() / 100,
    color: color_hex(self.color),
    left: (self.insets[0] * 12700).round() / 12700,
    top: (self.insets[1] * 12700).round() / 12700,
    right: (self.insets[2] * 12700).round() / 12700,
    bottom: (self.insets[3] * 12700).round() / 12700,
    wrap: self.wrap,
    align: self.align,
    vertical: self.vertical,
  }
}

///|
fn shape_fill_source(color : String) -> String {
  if color.is_empty() {
    "<odA:noFill/>"
  } else {
    "<odA:solidFill><odA:srgbClr val=\"\{color}\"/></odA:solidFill>"
  }
}

///|
fn SheetShape::text_source(self : SheetShape) -> String raise @failure.Failure {
  let style = "sz=\"\{(self.size * 100).round().to_int()}\" b=\"\{if self.bold { 1 } else { 0 }}\" i=\"\{if self.italic { 1 } else { 0 }}\""
  let font = "<odA:latin typeface=\"\{escaped_attribute(self.font)}\"/>"
  let character = shape_fill_source(self.color) + font
  let paragraphs = self.text
    .split("\n")
    .to_array()
    .map(fn(text) raise @failure.Failure {
      "<odA:p><odA:pPr algn=\"\{if self.align == "center" { "ctr" } else if self.align == "right" { "r" } else { "l" }}\"><odA:defRPr \{style}>\{character}</odA:defRPr></odA:pPr><odA:r><odA:rPr \{style}>\{character}</odA:rPr><odA:t xml:space=\"preserve\">\{@xml.escape_text(text.to_owned())}</odA:t></odA:r><odA:endParaRPr \{style}>\{character}</odA:endParaRPr></odA:p>"
    })
    .join("")
  "<odXdr:txBody><odA:bodyPr lIns=\"\{picture_emu(self.left)}\" tIns=\"\{picture_emu(self.top)}\" rIns=\"\{picture_emu(self.right)}\" bIns=\"\{picture_emu(self.bottom)}\" wrap=\"\{if self.wrap { "square" } else { "none" }}\" anchor=\"\{if self.vertical == "center" { "ctr" } else if self.vertical == "bottom" { "b" } else { "t" }}\"><odA:noAutofit/></odA:bodyPr><odA:lstStyle/>\{paragraphs}</odXdr:txBody>"
}

///|
fn SheetShape::properties_source(
  self : SheetShape,
  rect : @layout.Border,
) -> String {
  "<odXdr:spPr>\{picture_transform(rect)}<odA:prstGeom prst=\"\{self.preset}\"><odA:avLst/></odA:prstGeom>\{shape_fill_source(self.fill)}<odA:ln w=\"\{picture_emu(self.line_width)}\">\{shape_fill_source(self.stroke)}</odA:ln></odXdr:spPr>"
}

///|
fn SheetShape::source(
  self : SheetShape,
  rect : @layout.Border,
  nv : String,
) -> String raise @failure.Failure {
  "<odXdr:sp xmlns:odXdr=\"\{picture_uri}\" xmlns:odA=\"\{picture_drawing_uri}\">\{nv}\{self.properties_source(rect)}\{self.text_source()}</odXdr:sp>"
}
