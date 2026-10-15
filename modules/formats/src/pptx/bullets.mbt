///|
fn bullet_style(
  theme : Theme,
  styles : Array[Ref],
  text : String,
  fallback : @layout.TextStyle,
) -> @layout.TextStyle raise @failure.Failure {
  let mut font = fallback.font
  let mut size = fallback.size
  let mut paint = fallback.color
  for item in styles {
    if item.child("buFontTx") is Some(_) {
      break
    }
    if item.child("buFont") is Some(source) {
      font = font_key(
        theme,
        source.node.attribute("typeface").unwrap_or(""),
        text,
        false,
        false,
      )
      break
    }
  }
  for item in styles {
    if item.child("buSzTx") is Some(_) {
      break
    }
    if item.child("buSzPts") is Some(source) {
      size = number(source.node.attribute("val").unwrap_or("0"), 100, 102400) /
        100
      break
    }
    if item.child("buSzPct") is Some(source) {
      size = fallback.size *
        number(source.node.attribute("val").unwrap_or("100000"), 1000, 400000) /
        100000
      break
    }
  }
  for item in styles {
    if item.child("buClrTx") is Some(_) {
      break
    }
    if item.child("buClr") is Some(source) {
      paint = color(theme, source)
      break
    }
  }
  @layout.TextStyle::new(font, size, paint)
}
