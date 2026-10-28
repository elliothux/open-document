///|
/// Return the embedded TrueType family name, preferring typographic Unicode
/// records and English Windows names. An absent or malformed name yields "".
pub fn TextProbe::font_family(
  self : TextProbe,
  index : Int32,
) -> String raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown source font")
  }
  guard self.fonts[index].font.name() is Ok(Some(table)) else { return "" }
  for id in [16, 1] {
    for priority in [0, 1, 2] {
      for record in table.records {
        if record.name_id != id ||
          record.value.length() > 512 ||
          record.value.length() % 2 != 0 {
          continue
        }
        let preferred = if priority == 0 {
          record.platform_id == 3 && record.language_id == 1033
        } else if priority == 1 {
          record.platform_id == 0
        } else {
          record.platform_id == 3
        }
        if !preferred {
          continue
        }
        let text = @utf16.decode(record.value, endianness=Big) catch { _ => "" }
        if !text.is_empty() &&
          text.length() <= 256 &&
          text.iter().all(c => c.to_int() >= 32 && c.to_int() != 127) {
          return text
        }
      }
    }
  }
  ""
}

///|
/// Read bold/italic flags from the embedded font rather than its PDF alias.
pub fn TextProbe::font_style(
  self : TextProbe,
  index : Int32,
) -> (Bool, Bool) raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown source font")
  }
  let font = self.fonts[index]
  let mut bold = match font.font.os2() {
    Ok(Some(table)) => table.weight_class >= 600
    _ => false
  }
  let mut italic = font.italic_angle != 0
  if font.font.face.reference_table(@common.Tag::from_string("OS/2"))
    is Ok(table) {
    let bytes = table.as_view()
    if bytes.length() >= 64 {
      let flags = bytes[62].to_int() * 256 + bytes[63].to_int()
      bold = bold || (flags & 32) != 0
      italic = italic || (flags & 1) != 0
    }
  }
  if font.font.face.reference_table(@common.Tag::from_string("head"))
    is Ok(table) {
    let bytes = table.as_view()
    if bytes.length() >= 46 {
      let flags = bytes[44].to_int() * 256 + bytes[45].to_int()
      bold = bold || (flags & 1) != 0
      italic = italic || (flags & 2) != 0
    }
  }
  (bold, italic)
}
