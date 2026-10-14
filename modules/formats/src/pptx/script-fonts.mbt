///|
fn font_script(text : String) -> String {
  // shortcut: infer the current common scripts; add language-sensitive Han mapping when that flow is supported.
  let character = text.get_char(0).map(ch => ch.to_int()).unwrap_or(0)
  if character >= 0x3040 && character <= 0x30ff {
    "Jpan"
  } else if character >= 0x4e00 && character <= 0x9fff {
    "Hans"
  } else if character >= 0xac00 && character <= 0xd7af {
    "Hang"
  } else if character >= 0x600 && character <= 0x6ff {
    "Arab"
  } else if character >= 0x590 && character <= 0x5ff {
    "Hebr"
  } else if character >= 0x900 && character <= 0x97f {
    "Deva"
  } else if character >= 0xe00 && character <= 0xe7f {
    "Thai"
  } else {
    "latin"
  }
}

///|
fn styled_text(
  theme : Theme,
  sources : Array[Ref],
  text : String,
  default_font : String,
) -> Array[(@layout.TextStyle, String)] raise @failure.Failure {
  let boundaries = @layout.grapheme_boundaries(text)
  let parts : Array[String] = []
  let mut start = 0
  let mut script = ""
  for index in 0..<(boundaries.length() - 1) {
    let a = boundaries[index]
    let b = boundaries[index + 1]
    let next = font_script(text[a:b].to_owned())
    if a > start && next != script {
      parts.push(text[start:a].to_owned())
      start = a
    }
    script = next
  }
  parts.push(text[start:].to_owned())
  parts.map(part => (text_style(theme, sources, part, default_font), part))
}
