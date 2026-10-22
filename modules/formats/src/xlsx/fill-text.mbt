///|
fn filled_text_units(block : @layout.TextBlock) -> Int {
  block.lines
  .iter()
  .flat_map(line => line.iter())
  .fold(init=0, (count, primitive) => {
    count +
    (match primitive {
      @layout.Text(text) => text.text.length()
      _ => 0
    })
  })
}

///|
fn filled_block(
  probe : @layout.TextProbe,
  spans : Array[@layout.Span],
  size : Double,
  profile : Map[String, String],
  width : Double,
  original : @layout.TextBlock,
) -> @layout.TextBlock raise @failure.Failure {
  let units = spans.fold(init=0, (units, span) => units + span.text.length())
  if original.lines.length() != 1 ||
    units == 0 ||
    original.widths[0] <= 0 ||
    original.widths[0] >= width {
    return original
  }
  let capacity = (32767 / units).min(32767 / spans.length())
  if capacity < 2 {
    guard original.widths[0] * 2 > width else {
      @failure.reject(
        "limit-exceeded", "Filled cell text exceeds the text budget",
      )
    }
    return original
  }
  let measure = fn(count : Int) -> @layout.TextBlock raise @failure.Failure {
    probe.span_block(
      Array::makei(count, _ => spans).flatten(),
      size,
      profile,
      width,
      false,
    )
  }
  let mut result = original
  let mut low = 1
  let mut high = 2
  // Shape complete copies so kerning and mixed styles determine the last value that fits.
  while true {
    let candidate = measure(high)
    if candidate.widths[0] > width {
      break
    }
    result = candidate
    low = high
    guard high < capacity else {
      @failure.reject(
        "limit-exceeded", "Filled cell text exceeds the text budget",
      )
    }
    high = (high * 2).min(capacity)
  }
  while low + 1 < high {
    let middle = (low + high) / 2
    let candidate = measure(middle)
    if candidate.widths[0] <= width {
      low = middle
      result = candidate
    } else {
      high = middle
    }
  }
  result
}
