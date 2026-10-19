///|
fn bullet_style(
  theme : Theme,
  styles : Array[Ref],
  text : String,
  fallback : @layout.TextStyle,
  numbered~ : Bool = false,
) -> @layout.TextStyle raise @failure.Failure {
  let variants = fallback.font.split("|").to_array()
  let mut font = if numbered { fallback.font } else { variants[0].to_owned() }
  let bullet_size = bullet_size(styles)
  let size = if bullet_size.unit == "point" {
    bullet_size.value
  } else {
    fallback.size * bullet_size.value / 100
  }
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
        numbered && variants.contains("bold"),
        numbered && variants.contains("italic"),
      )
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

///|
fn bullet_size(styles : Array[Ref]) -> TextSpacing raise @failure.Failure {
  for item in styles {
    if item.child("buSzTx") is Some(_) {
      break
    }
    if item.child("buSzPts") is Some(source) {
      return {
        unit: "point",
        value: number(source.node.attribute("val").unwrap_or("0"), 100, 102400) /
        100,
      }
    }
    if item.child("buSzPct") is Some(source) {
      return {
        unit: "percent",
        value: number(
          source.node.attribute("val").unwrap_or("100000"),
          1000,
          400000,
        ) /
        1000,
      }
    }
  }
  { unit: "percent", value: 100, }
}
